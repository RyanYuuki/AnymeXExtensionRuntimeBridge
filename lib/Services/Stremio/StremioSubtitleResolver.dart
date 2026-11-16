import 'dart:async';
import 'dart:convert';
import '../../../Models/Video.dart';
import '../../Logger.dart';
import 'Models/StremioManifest.dart';
import 'Models/StremioStream.dart';
import 'StremioHttpClient.dart';

class StremioSubtitleResolver {
  static Future<List<Track>> resolveSubtitles({
    required List<StremioManifest> installedAddons,
    required String type,
    required String videoId,
    StreamBehaviorHints? behaviorHints,
    String? streamUrl,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final filename = behaviorHints?.filename ?? _filenameFromUrl(streamUrl);
    final videoHash = behaviorHints?.videoHash;
    final videoSize = behaviorHints?.videoSize;

    final canonicalType = type.toLowerCase() == 'tv' ? 'series' : type.toLowerCase();

    final eligibleAddons = installedAddons.where((addon) {
      return addon.supportsResource('subtitles', canonicalType, videoId);
    }).toList();

    if (eligibleAddons.isEmpty) {
      return [];
    }

    final futures = eligibleAddons.map((addon) async {
      try {
        final url = StremioHttpClient.buildSubtitleUrl(
          addon.transportUrl,
          canonicalType,
          videoId,
          videoHash: videoHash,
          videoSize: videoSize,
          filename: filename,
        );

        final response = await StremioHttpClient.get(url, timeout: timeout);
        final decoded = jsonDecode(response);

        if (decoded is Map && decoded['subtitles'] is List) {
          final list = (decoded['subtitles'] as List)
              .whereType<Map>()
              .map((m) => StreamSubtitle.fromJson(Map<String, dynamic>.from(m)))
              .where((s) => s.url.isNotEmpty)
              .map((s) => Track(
                    file: s.url,
                    label: s.label != null && s.label!.isNotEmpty
                        ? '${s.label} (${addon.name})'
                        : '${s.lang} (${addon.name})',
                  ))
              .toList();
          return list;
        }
      } catch (e) {
        Logger.log('Subtitle fetch failed from ${addon.name} ($videoId): $e');
      }
      return <Track>[];
    });

    final results = await Future.wait(futures);
    return results.expand((list) => list).toList();
  }

  static String? _filenameFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      final segment = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
      if (segment != null && segment.contains('.')) {
        return Uri.decodeComponent(segment);
      }
    } catch (_) {}
    return null;
  }
}
