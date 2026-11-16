import 'dart:convert';
import 'Models/StremioManifest.dart';
import 'StremioHttpClient.dart';

class StremioConfigManager {
  static bool isConfigurable(StremioManifest manifest) {
    return manifest.behaviorHints.configurable ||
        manifest.behaviorHints.configurationRequired ||
        manifest.config.isNotEmpty;
  }

  static String getConfigurePageUrl(String manifestUrl) {
    final baseUrl = StremioHttpClient.addonTransportBaseUrl(manifestUrl);
    return '$baseUrl/configure';
  }

  static String encodeConfiguredManifestUrl(String baseManifestUrl, Map<String, dynamic> config) {
    final normalized = StremioHttpClient.normalizeManifestUrl(baseManifestUrl);
    final baseUrl = StremioHttpClient.addonTransportBaseUrl(normalized);
    final querySplit = normalized.split('?');
    final query = querySplit.length > 1 ? '?${querySplit[1]}' : '';

    final jsonStr = jsonEncode(config);
    final encodedConfig = Uri.encodeComponent(jsonStr);

    return '$baseUrl/$encodedConfig/manifest.json$query';
  }

  static Map<String, dynamic>? extractConfigFromUrl(String manifestUrl) {
    final normalized = StremioHttpClient.normalizeManifestUrl(manifestUrl);
    final pathWithoutManifest = normalized.split('?').first.replaceAll(RegExp(r'/manifest\.json$', caseSensitive: false), '');
    final lastSegment = pathWithoutManifest.split('/').last;

    try {
      final decodedSegment = Uri.decodeComponent(lastSegment);
      final json = jsonDecode(decodedSegment);
      if (json is Map<String, dynamic>) {
        return json;
      }
    } catch (_) {}
    return null;
  }
}
