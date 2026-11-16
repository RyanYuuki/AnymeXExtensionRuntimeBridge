import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class StremioHttpClient {
  static final http.Client _client = http.Client();
  static final Map<String, Future<String>> _inFlightRequests = {};

  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Stremio/4.4.168';

  static String normalizeManifestUrl(String rawUrl) {
    var trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return trimmed;

    trimmed = trimmed.split('#').first;

    if (trimmed.startsWith('stremio://')) {
      final withoutScheme = trimmed.substring('stremio://'.length);
      final isLocal = withoutScheme.startsWith('127.0.0.1') ||
          withoutScheme.startsWith('localhost') ||
          withoutScheme.startsWith('192.168.') ||
          withoutScheme.startsWith('10.');
      trimmed = (isLocal ? 'http://' : 'https://') + withoutScheme;
    } else if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }

    final querySplit = trimmed.split('?');
    var path = querySplit.first;
    final query = querySplit.length > 1 ? '?${querySplit[1]}' : '';

    path = path.replaceAll(RegExp(r'/+$'), '');
    if (!path.toLowerCase().endsWith('/manifest.json')) {
      path = '$path/manifest.json';
    }

    return '$path$query';
  }

  static String addonTransportBaseUrl(String manifestUrl) {
    final path = manifestUrl.split('?').first;
    return path.replaceAll(RegExp(r'/manifest\.json$', caseSensitive: false), '');
  }

  static String encodePathSegment(String input) {
    const unreserved = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~';
    final bytes = utf8.encode(input);
    final buffer = StringBuffer();
    for (final byte in bytes) {
      final char = String.fromCharCode(byte);
      if (unreserved.contains(char)) {
        buffer.write(char);
      } else {
        buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return buffer.toString();
  }

  static String buildResourceUrl(
    String manifestUrl, {
    required String resource,
    required String type,
    required String id,
    String? extraPathSegment,
  }) {
    final baseUrl = addonTransportBaseUrl(manifestUrl);
    final encodedId = encodePathSegment(id);
    final querySplit = manifestUrl.split('?');
    final query = querySplit.length > 1 ? '?${querySplit[1]}' : '';

    final path = (extraPathSegment != null && extraPathSegment.isNotEmpty)
        ? '$baseUrl/$resource/$type/$encodedId/$extraPathSegment.json'
        : '$baseUrl/$resource/$type/$encodedId.json';

    return '$path$query';
  }

  static String buildCatalogUrl(
    String manifestUrl,
    String type,
    String catalogId, {
    String? search,
    String? genre,
    int? skip,
  }) {
    final extraParts = <String>[];
    if (search != null && search.trim().isNotEmpty) {
      extraParts.add('search=${encodePathSegment(search.trim())}');
    }
    if (genre != null && genre.trim().isNotEmpty) {
      extraParts.add('genre=${encodePathSegment(genre.trim())}');
    }
    if (skip != null && skip > 0) {
      extraParts.add('skip=$skip');
    }

    final extraSegment = extraParts.isNotEmpty ? extraParts.join('&') : null;

    return buildResourceUrl(
      manifestUrl,
      resource: 'catalog',
      type: type,
      id: catalogId,
      extraPathSegment: extraSegment,
    );
  }

  static String buildMetaUrl(String manifestUrl, String type, String id) {
    return buildResourceUrl(
      manifestUrl,
      resource: 'meta',
      type: type,
      id: id,
    );
  }

  static String buildStreamUrl(String manifestUrl, String type, String videoId) {
    return buildResourceUrl(
      manifestUrl,
      resource: 'stream',
      type: type,
      id: videoId,
    );
  }

  static String buildSubtitleUrl(
    String manifestUrl,
    String type,
    String videoId, {
    String? videoHash,
    int? videoSize,
    String? filename,
  }) {
    final extraParts = <String>[];
    if (videoHash != null && videoHash.isNotEmpty) {
      extraParts.add('videoHash=${encodePathSegment(videoHash)}');
    }
    if (videoSize != null && videoSize > 0) {
      extraParts.add('videoSize=$videoSize');
    }
    if (filename != null && filename.isNotEmpty) {
      extraParts.add('filename=${encodePathSegment(filename)}');
    }

    final extraSegment = extraParts.isNotEmpty ? extraParts.join('&') : null;

    final canonicalType = type.toLowerCase() == 'tv' ? 'series' : type.toLowerCase();

    return buildResourceUrl(
      manifestUrl,
      resource: 'subtitles',
      type: canonicalType,
      id: videoId,
      extraPathSegment: extraSegment,
    );
  }

  static Future<String> get(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_inFlightRequests.containsKey(url)) {
      return _inFlightRequests[url]!;
    }

    final completer = Completer<String>();
    _inFlightRequests[url] = completer.future;

    try {
      final reqHeaders = <String, String>{
        'User-Agent': defaultUserAgent,
        'Accept': 'application/json, text/plain, */*',
        ...?headers,
      };

      final response = await _client.get(Uri.parse(url), headers: reqHeaders).timeout(timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = utf8.decode(response.bodyBytes);
        completer.complete(body);
        return body;
      } else {
        throw http.ClientException('HTTP ${response.statusCode}: ${response.reasonPhrase}', Uri.parse(url));
      }
    } catch (e, stack) {
      completer.completeError(e, stack);
      rethrow;
    } finally {
      unawaited(_inFlightRequests.remove(url));
    }
  }

  static Future<dynamic> getJson(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final text = await get(url, headers: headers, timeout: timeout);
    return jsonDecode(text);
  }
}
