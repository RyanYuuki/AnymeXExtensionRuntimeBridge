import 'dart:convert';
import 'package:http/http.dart' as http;

class FetchBridge {
  static final http.Client _client = http.Client();

  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static Future<String> executeFetch(
    String url,
    String method,
    String headersJson,
    String bodyKind,
    String bodyValue,
    bool followRedirects,
  ) async {
    String effectiveUrl = url;
    if (effectiveUrl.contains('api.themoviedb.org')) {
      effectiveUrl = effectiveUrl.replaceFirst('api.themoviedb.org', 'api.tmdb.org');
    }
    if (effectiveUrl.contains('arm.haglund.dev/api/v2/tmdb')) {
      if (effectiveUrl.contains('id=tt')) {
        effectiveUrl = effectiveUrl.replaceFirst('/api/v2/tmdb', '/api/v2/imdb');
      } else {
        effectiveUrl = effectiveUrl.replaceFirst('/api/v2/tmdb', '/api/v2/themoviedb');
      }
    }
    if (effectiveUrl.contains('arm.haglund.dev/api/v2/themoviedb?id=tt')) {
      effectiveUrl = effectiveUrl.replaceFirst('/themoviedb?id=', '/imdb?id=');
    }
    if (effectiveUrl.contains('arm.haglund.dev/api/v2/imdb?id=') &&
        !effectiveUrl.contains('id=tt')) {
      effectiveUrl = effectiveUrl.replaceFirst('/imdb?id=', '/themoviedb?id=');
    }

    try {
      final uri = Uri.parse(effectiveUrl);
      final request = http.Request(method, uri);
      request.followRedirects = followRedirects;

      request.headers['User-Agent'] = defaultUserAgent;

      if (headersJson.isNotEmpty && headersJson != '{}') {
        try {
          final decoded = jsonDecode(headersJson);
          if (decoded is Map) {
            decoded.forEach((key, val) {
              request.headers[key.toString()] = val.toString();
            });
          }
        } catch (_) {}
      }

      if (bodyKind == 'text') {
        request.body = bodyValue;
      } else if (bodyKind == 'base64' && bodyValue.isNotEmpty) {
        request.bodyBytes = base64Decode(bodyValue);
      }

      final fetchTimeout = (effectiveUrl.contains('api.tmdb.org') || effectiveUrl.contains('api.themoviedb.org'))
          ? const Duration(seconds: 4)
          : const Duration(seconds: 8);
      final streamedResponse = await _client.send(request).timeout(fetchTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _buildResponseJson(response, effectiveUrl);
      }

      if (effectiveUrl.contains('api.themoviedb.org')) {
        final fallbackBody = await _resolveTmdbFallback(effectiveUrl);
        if (fallbackBody != null) {
          return jsonEncode({
            'ok': true,
            'status': 200,
            'statusText': 'OK',
            'url': effectiveUrl,
            'headers': {'content-type': 'application/json;charset=utf-8'},
            'body': fallbackBody,
            'bodyBase64': base64Encode(utf8.encode(fallbackBody)),
          });
        }
      }

      return _buildResponseJson(response, effectiveUrl);
    } catch (e) {
      if (effectiveUrl.contains('api.themoviedb.org')) {
        try {
          final fallbackBody = await _resolveTmdbFallback(effectiveUrl);
          if (fallbackBody != null) {
            return jsonEncode({
              'ok': true,
              'status': 200,
              'statusText': 'OK',
              'url': effectiveUrl,
              'headers': {'content-type': 'application/json;charset=utf-8'},
              'body': fallbackBody,
              'bodyBase64': base64Encode(utf8.encode(fallbackBody)),
            });
          }
        } catch (_) {}
      }

      final errorResult = {
        'ok': false,
        'status': 500,
        'statusText': e.toString(),
        'url': effectiveUrl,
        'headers': <String, String>{},
        'body': '',
        'bodyBase64': '',
      };
      return jsonEncode(errorResult);
    }
  }

  static String _buildResponseJson(http.Response response, String fallbackUrl) {
    final responseBytes = response.bodyBytes;
    final bodyBase64 = base64Encode(responseBytes);
    String bodyText;
    try {
      bodyText = utf8.decode(responseBytes);
    } catch (_) {
      bodyText = latin1.decode(responseBytes);
    }

    final outHeaders = <String, String>{};
    response.headers.forEach((k, v) {
      outHeaders[k.toLowerCase()] = v;
    });

    final result = {
      'ok': response.statusCode >= 200 && response.statusCode < 300,
      'status': response.statusCode,
      'statusText': response.reasonPhrase ?? '',
      'url': response.request?.url.toString() ?? fallbackUrl,
      'headers': outHeaders,
      'body': bodyText,
      'bodyBase64': bodyBase64,
    };

    return jsonEncode(result);
  }

  static Future<String?> _resolveTmdbFallback(String tmdbUrl) async {
    try {
      final uri = Uri.parse(tmdbUrl);
      final path = uri.path;

      if (path.contains('/find/')) {
        final segments = uri.pathSegments;
        final findIndex = segments.indexOf('find');
        if (findIndex != -1 && findIndex + 1 < segments.length) {
          final id = segments[findIndex + 1];
          if (id.startsWith('tt')) {
            var metaRes = await _client.get(Uri.parse('https://v3-cinemeta.strem.io/meta/series/$id.json'));
            if (metaRes.statusCode != 200) {
              metaRes = await _client.get(Uri.parse('https://v3-cinemeta.strem.io/meta/movie/$id.json'));
            }
            if (metaRes.statusCode == 200) {
              final metaData = jsonDecode(metaRes.body)['meta'] as Map? ?? {};
              final name = metaData['name']?.toString() ?? '';
              final moviedbId = metaData['moviedb_id'] ?? 0;
              return jsonEncode({
                'movie_results': [
                  {'id': moviedbId, 'title': name, 'name': name}
                ],
                'tv_results': [
                  {'id': moviedbId, 'name': name, 'title': name}
                ],
              });
            }
          }
        }
      }

      if (path.contains('/external_ids')) {
        final segments = uri.pathSegments;
        final extIndex = segments.indexOf('external_ids');
        if (extIndex > 0) {
          final numericId = segments[extIndex - 1];
          final armRes = await _client.get(Uri.parse('https://arm.haglund.dev/api/v2/themoviedb?id=$numericId'));
          if (armRes.statusCode == 200) {
            final armData = jsonDecode(armRes.body);
            if (armData is List && armData.isNotEmpty && armData[0] is Map) {
              final imdb = armData[0]['imdb']?.toString() ?? '';
              return jsonEncode({
                'id': int.tryParse(numericId) ?? numericId,
                'imdb_id': imdb,
              });
            }
          }
        }
      }

      final isTv = path.contains('/tv/');
      final isMovie = path.contains('/movie/');
      if (isTv || isMovie) {
        final segments = uri.pathSegments;
        final targetIndex = isTv ? segments.indexOf('tv') : segments.indexOf('movie');
        if (targetIndex != -1 && targetIndex + 1 < segments.length) {
          final numericId = segments[targetIndex + 1];
          if (int.tryParse(numericId) != null) {
            final armRes = await _client.get(Uri.parse('https://arm.haglund.dev/api/v2/themoviedb?id=$numericId'));
            if (armRes.statusCode == 200) {
              final armData = jsonDecode(armRes.body);
              if (armData is List && armData.isNotEmpty && armData[0] is Map) {
                final imdb = armData[0]['imdb']?.toString() ?? '';
                final type = isTv ? 'series' : 'movie';
                final cinemetaRes = await _client.get(Uri.parse('https://v3-cinemeta.strem.io/meta/$type/$imdb.json'));
                if (cinemetaRes.statusCode == 200) {
                  final meta = jsonDecode(cinemetaRes.body)['meta'] as Map? ?? {};
                  final name = meta['name']?.toString() ?? '';
                  final released = meta['released']?.toString() ?? '';
                  return jsonEncode({
                    'id': int.tryParse(numericId) ?? numericId,
                    'name': name,
                    'title': name,
                    'first_air_date': released,
                    'release_date': released,
                  });
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
