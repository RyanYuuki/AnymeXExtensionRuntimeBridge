import 'dart:async';
import 'dart:convert';

import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:http/http.dart' as http;

import '../../../Logger.dart';
import '../../JsEngine.dart';
import '../../Mangayomi/http/m_client.dart';

class PaperbackJsEngine {
  PaperbackJsEngine._internal();
  static final PaperbackJsEngine instance = PaperbackJsEngine._internal();

  late final JavascriptRuntime _runtime;
  Completer<void>? _initCompleter;
  final http.Client _client = MClient.init();

  final Set<String> _loadedModules = {};

  Future<void> init() {
    if (_initCompleter?.isCompleted ?? false) {
      return _initCompleter!.future;
    }

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    _doInit();
    return _initCompleter!.future;
  }

  Future<void> _doInit() async {
    try {
      _runtime = await JsEngineEnv.instance.init();

      final setToGlobalObject = _runtime
          .evaluate("(key, val) => { globalThis[key] = val; }")
          .rawResult as JSInvokable;

      setToGlobalObject.invoke([
        '__paperback_bridge',
        (String payload) async {
          try {
            final data = jsonDecode(payload) as Map<String, dynamic>;
            final action = data['action'] as String;

            if (action == 'scheduleRequest') {
              return await _handleScheduleRequest(data['request'] as Map<String, dynamic>);
            }

            throw Exception('Unknown bridge action: $action');
          } catch (e) {
            return jsonEncode({'error': e.toString()});
          }
        }
      ]);

      await _injectPolyfills();

      _initCompleter?.complete();
    } catch (e, stack) {
      _initCompleter?.completeError(e, stack);
      _initCompleter = null;
    }
  }

  Future<String> _handleScheduleRequest(Map<String, dynamic> req) async {
    final url = req['url']?.toString() ?? '';
    final method = (req['method']?.toString() ?? 'GET').toUpperCase();
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': '*/*',
    };

    if (req['headers'] is Map) {
      (req['headers'] as Map).forEach((k, v) {
        if (k != null && v != null) {
          headers[k.toString()] = v.toString();
        }
      });
    }

    final body = req['body'];
    final uri = Uri.parse(url);

    http.Response response;
    if (method == 'GET') {
      response = await _client.get(uri, headers: headers);
    } else if (method == 'POST') {
      response = await _client.post(uri, headers: headers, body: body);
    } else if (method == 'PUT') {
      response = await _client.put(uri, headers: headers, body: body);
    } else if (method == 'DELETE') {
      response = await _client.delete(uri, headers: headers, body: body);
    } else if (method == 'HEAD') {
      response = await _client.head(uri, headers: headers);
    } else {
      final customReq = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        customReq.body = body is String ? body : jsonEncode(body);
      }
      final streamed = await _client.send(customReq);
      response = await http.Response.fromStream(streamed);
    }

    final headerMap = <String, String>{};
    response.headers.forEach((k, v) {
      headerMap[k] = v;
    });

    final base64Body = base64Encode(response.bodyBytes);

    return jsonEncode({
      'status': response.statusCode,
      'headers': headerMap,
      'base64Data': base64Body,
    });
  }

  Future<void> _injectPolyfills() async {
    const polyfills = r'''
    // Base64 polyfills
    if (typeof btoa === 'undefined') {
      var _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
      globalThis.btoa = function(input) {
        var str = String(input);
        var output = '';
        for (var block = 0, charCode, i = 0, map = _chars;
             str.charAt(i | 0) || (map = '=', i % 1);
             output += map.charAt(63 & block >> 8 - i % 1 * 8)) {
          charCode = str.charCodeAt(i += 3/4);
          if (charCode > 0xFF) throw new Error("'btoa' failed: The string contains characters outside of Latin1.");
          block = block << 8 | charCode;
        }
        return output;
      };
    }

    if (typeof atob === 'undefined') {
      var _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
      globalThis.atob = function(input) {
        var str = String(input).replace(/[=]+$/, '');
        if (str.length % 4 == 1) throw new Error("'atob' failed: Not correctly encoded.");
        var output = '';
        for (var bc = 0, bs = 0, buffer, i = 0;
             buffer = str.charAt(i++);
             ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer,
               bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
          buffer = _chars.indexOf(buffer);
        }
        return output;
      };
    }

    function _base64ToArrayBuffer(base64) {
      if (!base64) return new ArrayBuffer(0);
      var binary_string = atob(base64);
      var len = binary_string.length;
      var bytes = new Uint8Array(len);
      for (var i = 0; i < len; i++) {
        bytes[i] = binary_string.charCodeAt(i);
      }
      return bytes.buffer;
    }

    // Paperback 0.9 Host Application Interface
    var Application = {
      _state: {},
      _selectors: {},
      _selectorCount: 0,

      getState: function(key) {
        return this._state[key];
      },
      setState: function(val, key) {
        this._state[key] = val;
      },
      getSecureState: function(key) {
        return this._state[key];
      },
      setSecureState: function(val, key) {
        this._state[key] = val;
      },
      resetAllState: function() {
        this._state = {};
      },

      getDefaultUserAgent: function() {
        return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
      },
      isResourceLimited: function() {
        return false;
      },
      sleep: function(ms) {
        return new Promise(function(resolve) {
          setTimeout(resolve, ms);
        });
      },

      decodeHTMLEntities: function(str) {
        if (!str || typeof str !== 'string') return str;
        return str
          .replace(/&amp;/g, '&')
          .replace(/&lt;/g, '<')
          .replace(/&gt;/g, '>')
          .replace(/&quot;/g, '"')
          .replace(/&#39;/g, "'")
          .replace(/&apos;/g, "'")
          .replace(/&#(\d+);/g, function(match, dec) {
            return String.fromCharCode(dec);
          })
          .replace(/&#x([0-9a-fA-F]+);/g, function(match, hex) {
            return String.fromCharCode(parseInt(hex, 16));
          });
      },

      arrayBufferToUTF8String: function(buf) {
        if (!buf) return '';
        if (typeof buf === 'string') return buf;
        var bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
        if (typeof TextDecoder !== 'undefined') {
          try {
            return new TextDecoder('utf-8').decode(bytes);
          } catch (e) {}
        }
        var str = '';
        for (var i = 0; i < bytes.length; i++) {
          str += String.fromCharCode(bytes[i]);
        }
        try {
          return decodeURIComponent(escape(str));
        } catch (e) {
          return str;
        }
      },

      base64Encode: function(buf) {
        if (!buf) return '';
        var bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
        var binary = '';
        for (var i = 0; i < bytes.byteLength; i++) {
          binary += String.fromCharCode(bytes[i]);
        }
        return btoa(binary);
      },

      base64Decode: function(str) {
        return _base64ToArrayBuffer(str);
      },

      formDidChange: function(id) {},
      invalidateDiscoverSections: function() {},
      registerInterceptor: function() {},
      unregisterInterceptor: function() {},

      Selector: function(target, method) {
        var id = 'sel_' + (++this._selectorCount);
        if (target && typeof target[method] === 'function') {
          this._selectors[id] = target[method].bind(target);
        } else {
          this._selectors[id] = function() {};
        }
        return id;
      },

      SelectorRegistry: {
        selector: function(id) {
          return (Application._selectors && Application._selectors[id]) || function() {};
        }
      },

      scheduleRequest: async function(req) {
        var payload = JSON.stringify({
          action: 'scheduleRequest',
          request: req
        });
        var resStr = await __paperback_bridge(payload);
        var parsed = JSON.parse(resStr);
        if (parsed.error) {
          throw new Error(parsed.error);
        }
        var buffer = _base64ToArrayBuffer(parsed.base64Data);
        return [{ status: parsed.status, headers: parsed.headers || {} }, buffer];
      },

      executeInWebView: async function(req) {
        return await this.scheduleRequest(req);
      }
    };

    globalThis.Application = Application;

    // Common JS root holder for paperback sources
    if (typeof globalThis.source === 'undefined') {
      globalThis.source = {};
    }
    ''';

    _runtime.evaluate(polyfills);
  }

  Future<void> loadModule({
    required String sourceId,
    required String sourceCode,
  }) async {
    await init();

    if (_loadedModules.contains(sourceId)) {
      return;
    }

    try {
      final wrapped = '''
      (() => {
        var exports = {};
        var module = { exports: exports };
        $sourceCode
        if (typeof source !== 'undefined') {
          globalThis.source = Object.assign(globalThis.source || {}, source);
        }
      })();
      ''';

      _runtime.evaluate(wrapped);
      _loadedModules.add(sourceId);
    } catch (e) {
      Logger.log("Error loading Paperback module $sourceId: $e");
      rethrow;
    }
  }

  Future<dynamic> call({
    required String sourceId,
    required String method,
    List<dynamic> params = const [],
  }) async {
    await init();

    final encodedParams = jsonEncode(params);

    final js = '''
    (async () => {
      var src = globalThis.source ? (globalThis.source['$sourceId'] || globalThis.source['$sourceId' + 'Extension']) : null;
      if (!src) {
        throw new Error("Paperback source '$sourceId' not found in globalThis.source");
      }
      var fn = src['$method'];
      if (typeof fn !== 'function') {
        throw new Error("Method '$method' not found on source '$sourceId'");
      }
      var args = JSON.parse('$encodedParams');
      var res = await fn.apply(src, args);
      return JSON.stringify(res);
    })()
    ''';

    try {
      final evalRes = await _runtime.evaluateAsync(js);
      final result = await _runtime.handlePromise(evalRes);
      final raw = result.rawResult;
      if (raw is String) {
        try {
          return jsonDecode(raw);
        } catch (_) {
          return raw;
        }
      }
      return raw;
    } catch (e) {
      Logger.log("Error in Paperback $sourceId.$method: $e");
      rethrow;
    }
  }

  Future<void> dispose() async {
    _initCompleter = null;
    _loadedModules.clear();
  }
}
