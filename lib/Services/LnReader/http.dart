import 'dart:convert';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:http/http.dart' as http;

import '../../ExtensionBridge.dart';

class JsHttpClient {
  late JavascriptRuntime runtime;
  JsHttpClient(this.runtime);

  void init() {
    http.Client client() {
      return AnymeXExtensionBridge.context.http ?? http.Client();
    }

    runtime.onMessage('http_head', (dynamic args) async {
      return await _toHttpResponse(client(), "HEAD", args);
    });
    runtime.onMessage('http_get', (dynamic args) async {
      return await _toHttpResponse(client(), "GET", args);
    });
    runtime.onMessage('http_post', (dynamic args) async {
      return await _toHttpResponse(client(), "POST", args);
    });
    runtime.onMessage('http_put', (dynamic args) async {
      return await _toHttpResponse(client(), "PUT", args);
    });
    runtime.onMessage('http_delete', (dynamic args) async {
      return await _toHttpResponse(client(), "DELETE", args);
    });
    runtime.onMessage('http_patch', (dynamic args) async {
      return await _toHttpResponse(client(), "PATCH", args);
    });
    runtime.evaluate('''
class Headers {
  constructor(init) {
    this._map = {};
    if (init) {
      if (init instanceof Headers) {
        init.forEach((v, k) => this.set(k, v));
      } else if (Array.isArray(init)) {
        for (var i = 0; i < init.length; i++) {
          this.append(init[i][0], init[i][1]);
        }
      } else if (typeof init === "object") {
        for (var k in init) {
          if (init.hasOwnProperty(k)) {
            this.set(k, init[k]);
          }
        }
      }
    }
  }
  get(name) {
    if (!name) return null;
    var target = String(name).toLowerCase();
    for (var k in this._map) {
      if (k.toLowerCase() === target) {
        return this._map[k];
      }
    }
    return null;
  }
  set(name, value) {
    if (!name) return;
    this.delete(name);
    this._map[String(name)] = String(value);
  }
  append(name, value) {
    var existing = this.get(name);
    this.set(name, existing ? existing + ", " + value : value);
  }
  has(name) {
    return this.get(name) !== null;
  }
  delete(name) {
    if (!name) return;
    var target = String(name).toLowerCase();
    for (var k in this._map) {
      if (k.toLowerCase() === target) {
        delete this._map[k];
      }
    }
  }
  forEach(callback) {
    for (var k in this._map) {
      if (this._map.hasOwnProperty(k)) {
        callback(this._map[k], k, this);
      }
    }
  }
  toJSON() {
    return this._map;
  }
}

class Response {
  constructor(url, result) {
    this.response = typeof result === "string" ? JSON.parse(result) : (result || {});
    this.url = this.response.url || url || "";
    this._headers = new Headers(this.response.headers || {});
  }
  get status() {
    return this.response.statusCode || 200;
  }
  get statusText() {
    return this.response.reasonPhrase || "";
  }
  get ok() {
    return this.status >= 200 && this.status <= 299;
  }
  get redirected() {
    return !!this.response.isRedirect;
  }
  get headers() {
    return this._headers;
  }
  get body() {
    return this.response.body || "";
  }
  json() {
    var val = JSON.parse(this.body);
    return new Promise(function(resolve) {
      resolve(val);
    });
  }
  text() {
    var val = this.body;
    return new Promise(function(resolve) {
      resolve(val);
    });
  }
}

async function fetchApi(url, init) {
  var method = init && init.method ? init.method.toLowerCase() : "get";
  var headers = init && init.headers;
  if (headers && typeof headers.toJSON === "function") {
    headers = headers.toJSON();
  }
  var body = init && init.body;
  if (body && typeof body.toJSON === "function") {
    body = body.toJSON();
  }
  var result = await sendMessage(
    "http_" + method,
    JSON.stringify([url, headers, body])
  );
  return new Response(url, result);
}

globalThis.Headers = Headers;
globalThis.Response = Response;
globalThis.fetch = fetchApi;
''');
  }
}

Future<String> _toHttpResponse(http.Client client, String method, List args) async {
  final url = args[0] as String;
  final headers = (args[1] as Map?)?.toMapStringString ?? <String, String>{};

  if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
    headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  }
  if (!headers.keys.any((k) => k.toLowerCase() == 'accept')) {
    headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8';
  }
  if (!headers.keys.any((k) => k.toLowerCase() == 'accept-language')) {
    headers['Accept-Language'] = 'en-US,en;q=0.9';
  }

  final rawBody = args.length >= 3 ? args[2] : null;
  String? requestBody;

  if (rawBody is Map && rawBody['_formData'] == true) {
    final fields = (rawBody['fields'] as Map?)?.toMapStringString ?? {};
    requestBody = fields.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    if (!headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
    }
  } else if (rawBody is Map && rawBody.containsKey('_data')) {
    final data = rawBody['_data'] as List<dynamic>;
    requestBody = data
        .map((e) => '${Uri.encodeQueryComponent(e[0].toString())}=${Uri.encodeQueryComponent(e[1].toString())}')
        .join('&');
    if (!headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
    }
  } else if (rawBody is String) {
    requestBody = rawBody;
  } else if (rawBody != null) {
    final isJson = headers.entries.any(
      (e) => e.key.toLowerCase() == 'content-type' && e.value.contains('application/json'),
    );
    if (isJson) {
      requestBody = json.encode(rawBody);
    } else if (rawBody is Map) {
      requestBody = rawBody.entries
          .map((e) => '${Uri.encodeQueryComponent(e.key.toString())}=${Uri.encodeQueryComponent(e.value.toString())}')
          .join('&');
      if (!headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
        headers['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
      }
    }
  }

  final request = http.Request(method, Uri.parse(url));
  request.headers.addAll(headers);
  if (requestBody != null) {
    request.body = requestBody;
  }

  final response = await client.send(request);
  final bodyBytes = await response.stream.toBytes();
  final responseBody = utf8.decode(bodyBytes, allowMalformed: true);

  final resMap = <String, dynamic>{
    'url': response.request?.url.toString() ?? url,
    'statusCode': response.statusCode,
    'reasonPhrase': response.reasonPhrase,
    'isRedirect': response.isRedirect,
    'persistentConnection': response.persistentConnection,
    'headers': response.headers,
    'body': responseBody,
  };

  return jsonEncode(resMap);
}

extension ToMapExtension on Map? {
  Map<String, dynamic>? get toMapStringDynamic {
    return this?.map((key, value) => MapEntry(key.toString(), value));
  }

  Map<String, String>? get toMapStringString {
    return this?.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }
}
