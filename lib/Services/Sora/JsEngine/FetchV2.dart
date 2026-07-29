import 'dart:convert';

import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:http/http.dart' as http;

import '../../Mangayomi/http/m_client.dart';

class FetchV2 {
  final JavascriptRuntime runtime;
  FetchV2(this.runtime);

  final http.Client _client = MClient.init();

  static const _defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Connection': 'keep-alive',
  };

  Future<void> inject() async {
    runtime.evaluate(r'''
async function fetchv2(url, headers = {}, method = "GET", body = null) {
  const payload = JSON.stringify({
    type: "fetchv2",
    url,
    headers,
    method,
    body
  });
  const res = await sendMessage("bridge", payload);

  return {
    status: res.status,
    headers: res.headers,
    ok: res.status >= 200 && res.status < 300,
    json: () => Promise.resolve(JSON.parse(res.body)),
    text: () => Promise.resolve(res.body)
  };
}

// alias
const fetch = fetchv2;
''');
  }

  Future<dynamic> handle(Map data) async {
    final url = data['url'] as String;
    var method = (data['method'] as String? ?? 'GET').toUpperCase();
    var body = data['body'];

    final headers = Map<String, String>.from(_defaultHeaders);

    var extHeaders = data['headers'] as Map?;
    if (extHeaders != null) {
      final hasHeaders = extHeaders.containsKey('headers') || extHeaders.containsKey('Headers');
      final hasMethod = extHeaders.containsKey('method') || extHeaders.containsKey('Method');
      final hasBody = extHeaders.containsKey('body') || extHeaders.containsKey('Body');
      if (hasHeaders || hasMethod || hasBody) {
        final optMethod = extHeaders['method'] ?? extHeaders['Method'];
        if (optMethod != null) {
          method = optMethod.toString().toUpperCase();
        }
        final optBody = extHeaders['body'] ?? extHeaders['Body'];
        if (optBody != null) {
          body = optBody;
        }
        extHeaders = (extHeaders['headers'] ?? extHeaders['Headers']) as Map?;
      }
    }

    if (extHeaders != null) {
      extHeaders.forEach((k, v) {
        headers[k.toString()] = v.toString();
      });
    }

    final normalizedHeaders = _normalizeHeaderKeys(headers);

    try {
      final uri = Uri.parse(url);

      http.Response response;

      if (method == 'GET') {
        response = await _client.get(uri, headers: normalizedHeaders);
      } else if (method == 'HEAD') {
        response = await _client.head(uri, headers: normalizedHeaders);
      } else {
        final req = http.Request(method, uri)..headers.addAll(normalizedHeaders);

        if (body != null) {
          req.body = body is String ? body : jsonEncode(body);
        }

        final streamed = await _client.send(req);
        response = await http.Response.fromStream(streamed);
      }

      final headerMap = <String, dynamic>{};
      response.headers.forEach((k, v) {
        headerMap[k] = v;
      });

      return {
        'status': response.statusCode,
        'headers': headerMap,
        'body': response.body,
      };
    } catch (e) {
      throw Exception('fetchv2 failed: $e');
    }
  }

  Map<String, String> _normalizeHeaderKeys(Map<String, String> headers) {
    final Map<String, String> normalized = {};
    headers.forEach((key, value) {
      final String normalizedKey = key.split('-').map((part) {
        if (part.isEmpty) return '';
        final lower = part.toLowerCase();
        if (lower == 'ua') return 'UA';
        if (lower == 'gpc') return 'GPC';
        if (lower == 'ch') return 'CH';
        return part[0].toUpperCase() + part.substring(1).toLowerCase();
      }).join('-');
      normalized[normalizedKey] = value;
    });
    return normalized;
  }
}
