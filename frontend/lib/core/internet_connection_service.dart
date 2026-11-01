import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'backend_api_client.dart';
import 'backend_connection.dart';

/// Checks whether the internet services required by GoldBrain are reachable.
///
/// An active Wi-Fi/Ethernet adapter is not enough: captive portals and VPN/DNS
/// failures can leave an adapter "connected" without usable internet. This
/// probe therefore validates a small HTTPS response from either of two actual
/// market providers used by the application.
class InternetConnectionService {
  InternetConnectionService({
    http.Client? client,
    GoldBrainBackendClient? backend,
    this.timeout = const Duration(seconds: 6),
    List<Uri>? probeUris,
  }) : _client = client ?? http.Client(),
       _backend =
           backend ??
           (client == null && probeUris == null
               ? BackendConnection.instance.api
               : null),
       _ownsClient = client == null,
       probeUris = List.unmodifiable(
         probeUris ??
             <Uri>[
               Uri.parse('https://zarix.online/api/?endpoint=summary'),
               Uri.parse('https://api.gold-api.com/symbols'),
             ],
       );

  factory InternetConnectionService.defaults({
    http.Client? client,
    Duration timeout = const Duration(seconds: 6),
  }) {
    return InternetConnectionService(client: client, timeout: timeout);
  }

  final http.Client _client;
  final GoldBrainBackendClient? _backend;
  final bool _ownsClient;
  final Duration timeout;
  final List<Uri> probeUris;

  Future<bool> hasInternetAccess() async {
    if (_backend != null) {
      try {
        final health = await _backend.health().timeout(timeout);
        return health.status == 'ok';
      } catch (_) {
        return false;
      }
    }
    if (probeUris.isEmpty) return false;

    // Resolve on the first successful provider. Only if all probes fail do we
    // report offline, so a blocked provider/VPN route cannot hide a working one.
    final result = Completer<bool>();
    var remaining = probeUris.length;
    for (final uri in probeUris) {
      unawaited(
        _probe(uri).then((reachable) {
          if (result.isCompleted) return;
          if (reachable) {
            result.complete(true);
            return;
          }
          remaining--;
          if (remaining == 0) result.complete(false);
        }),
      );
    }
    return result.future;
  }

  Future<bool> _probe(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: const {'accept': 'application/json'})
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      if (response.bodyBytes.isEmpty ||
          response.bodyBytes.length > 512 * 1024) {
        return false;
      }

      // Reject captive-portal HTML. Both configured endpoints return JSON.
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map || decoded is List;
    } on TimeoutException {
      return false;
    } on http.ClientException {
      return false;
    } on FormatException {
      return false;
    } catch (_) {
      return false;
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
