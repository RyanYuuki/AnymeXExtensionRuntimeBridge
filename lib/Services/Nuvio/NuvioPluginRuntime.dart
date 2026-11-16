import 'dart:async';
import 'dart:convert';
import 'package:flutter_qjs/flutter_qjs.dart';
import '../../Logger.dart';
import 'Bridges/CryptoBridge.dart';
import 'Bridges/DomBridge.dart';
import 'Bridges/FetchBridge.dart';
import 'Models/PluginManifest.dart';
import 'NuvioJsPolyfills.dart';

class NuvioPluginRuntime {
  static bool _searchPaused = false;

  static void setSearchPaused(bool paused) {
    _searchPaused = paused;
  }

  static String _parseUrl(String url, String base) {
    try {
      Uri uri;
      if (base.isNotEmpty) {
        final baseUri = Uri.parse(base);
        uri = baseUri.resolve(url);
      } else {
        uri = Uri.parse(url);
      }
      return jsonEncode({
        'href': uri.toString(),
        'protocol': uri.scheme.isNotEmpty ? '${uri.scheme}:' : '',
        'host': uri.host + (uri.hasPort ? ':${uri.port}' : ''),
        'hostname': uri.host,
        'port': uri.hasPort ? uri.port.toString() : '',
        'pathname': uri.path.isNotEmpty ? uri.path : '/',
        'search': uri.hasQuery ? '?${uri.query}' : '',
        'hash': uri.hasFragment ? '#${uri.fragment}' : '',
        'origin': uri.origin,
      });
    } catch (_) {
      return jsonEncode({
        'href': url,
        'protocol': '',
        'host': '',
        'hostname': '',
        'port': '',
        'pathname': '',
        'search': '',
        'hash': '',
        'origin': '',
      });
    }
  }

  static void _freeJs(dynamic ref) {
    if (ref == null) return;
    try {
      ref.destroy();
    } catch (_) {
      try {
        ref.free();
      } catch (_) {}
    }
  }

  static void _setupBridges({
    required JavascriptRuntime runtime,
    required DomBridge domBridge,
    required Completer<dynamic> resultCompleter,
    required String scraperId,
    required Map<String, dynamic>? scraperSettings,
    required String tmdbApiKey,
    required String callArgsJson,
  }) {
    final setToGlobal = runtime.evaluate("(key, val) => { this[key] = val; }").rawResult as JSInvokable;
    setToGlobal.invoke(['__get_scraper_id', () => scraperId]);
    setToGlobal.invoke(['__get_scraper_settings', () => jsonEncode(scraperSettings ?? {})]);
    setToGlobal.invoke(['__get_tmdb_api_key', () => tmdbApiKey]);
    setToGlobal.invoke(['__get_call_args', () => callArgsJson]);
    setToGlobal.invoke(['__capture_result', (dynamic res) {
      if (!resultCompleter.isCompleted) {
        resultCompleter.complete(res);
      }
    }]);
    setToGlobal.invoke(['__native_fetch', (dynamic url, dynamic method, dynamic headers, dynamic kind, dynamic val, dynamic red) => FetchBridge.executeFetch(url?.toString() ?? '', method?.toString() ?? 'GET', headers?.toString() ?? '{}', kind?.toString() ?? 'NONE', val?.toString() ?? '', red == true)]);
    setToGlobal.invoke(['__cheerio_load', (dynamic html) => domBridge.load(html?.toString() ?? '')]);
    setToGlobal.invoke(['__cheerio_select', (dynamic docId, dynamic sel) => domBridge.select(docId?.toString() ?? '', sel?.toString() ?? '')]);
    setToGlobal.invoke(['__cheerio_find', (dynamic docId, dynamic parentId, dynamic sel) => domBridge.find(docId?.toString() ?? '', parentId?.toString() ?? '', sel?.toString() ?? '')]);
    setToGlobal.invoke(['__cheerio_text', (dynamic docId, dynamic idsCsv) => domBridge.text(docId?.toString() ?? '', idsCsv?.toString() ?? '')]);
    setToGlobal.invoke(['__cheerio_inner_html', (dynamic docId, dynamic id) => domBridge.innerHtml(docId?.toString() ?? '', id?.toString() ?? '')]);
    setToGlobal.invoke(['__cheerio_html', (dynamic docId, dynamic id) => domBridge.html(docId?.toString() ?? '', id?.toString() ?? '')]);
    setToGlobal.invoke(['__cheerio_attr', (dynamic docId, dynamic id, dynamic name) => domBridge.attr(docId?.toString() ?? '', id?.toString() ?? '', name?.toString() ?? '')]);
    setToGlobal.invoke(['__cheerio_next', (dynamic docId, dynamic id) => domBridge.next(docId?.toString() ?? '', id?.toString() ?? '')]);
    setToGlobal.invoke(['__cheerio_prev', (dynamic docId, dynamic id) => domBridge.prev(docId?.toString() ?? '', id?.toString() ?? '')]);

    setToGlobal.invoke(['__crypto_digest_hex_raw', (dynamic algo, dynamic hex) => CryptoBridge.digest(algo?.toString() ?? '', hex?.toString() ?? '')]);
    setToGlobal.invoke(['__crypto_hmac_hex_raw', (dynamic algo, dynamic key, dynamic hex) => CryptoBridge.hmac(algo?.toString() ?? '', key?.toString() ?? '', hex?.toString() ?? '')]);
    setToGlobal.invoke(['__crypto_pbkdf2_hex', (dynamic pass, dynamic salt, dynamic iter, dynamic keySize, dynamic algo) => CryptoBridge.pbkdf2(pass?.toString() ?? '', salt?.toString() ?? '', int.tryParse(iter?.toString() ?? '') ?? 1000, int.tryParse(keySize?.toString() ?? '') ?? 256, algo?.toString() ?? 'SHA-256')]);
    setToGlobal.invoke(['__crypto_aes_encrypt_hex', (dynamic mode, dynamic key, dynamic iv, dynamic data) => CryptoBridge.aesEncrypt(mode?.toString() ?? '', key?.toString() ?? '', iv?.toString() ?? '', data?.toString() ?? '')]);
    setToGlobal.invoke(['__crypto_aes_decrypt_hex', (dynamic mode, dynamic key, dynamic iv, dynamic data) => CryptoBridge.aesDecrypt(mode?.toString() ?? '', key?.toString() ?? '', iv?.toString() ?? '', data?.toString() ?? '')]);
    setToGlobal.invoke(['__crypto_get_random_values_hex', (dynamic len) => CryptoBridge.getRandomValues(int.tryParse(len?.toString() ?? '') ?? 16)]);
    setToGlobal.invoke(['__crypto_utf8_to_hex', (dynamic str) => CryptoBridge.utf8ToHex(str?.toString() ?? '')]);
    setToGlobal.invoke(['__crypto_hex_to_utf8', (dynamic hex) => CryptoBridge.hexToUtf8(hex?.toString() ?? '')]);
    setToGlobal.invoke(['__parse_url', (dynamic url, dynamic base) => _parseUrl(url?.toString() ?? '', base?.toString() ?? '')]);
    _freeJs(setToGlobal);
  }

  static Future<List<PluginRuntimeResult>> executePlugin({
    required String code,
    required String tmdbId,
    required String mediaType,
    int? season,
    int? episode,
    required String scraperId,
    Map<String, dynamic>? scraperSettings,
    String tmdbApiKey = '',
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_searchPaused) {
      return [];
    }

    final runtime = getJavascriptRuntime();
    final domBridge = DomBridge();
    final resultCompleter = Completer<dynamic>();

    final callArgsJson = jsonEncode({
      'tmdbId': tmdbId,
      'mediaType': mediaType,
      'season': season,
      'episode': episode,
    });

    try {
      _setupBridges(
        runtime: runtime,
        domBridge: domBridge,
        resultCompleter: resultCompleter,
        scraperId: scraperId,
        scraperSettings: scraperSettings,
        tmdbApiKey: tmdbApiKey,
        callArgsJson: callArgsJson,
      );

      runtime.onMessage('nuvio_console_log', (dynamic args) {
        final text = (args is Map && args['msg'] != null) ? args['msg'].toString() : args.toString();
        Logger.log('[Nuvio JS Log] $text');
        return null;
      });

      runtime.onMessage('nuvio_console_error', (dynamic args) {
        final text = (args is Map && args['msg'] != null) ? args['msg'].toString() : args.toString();
        Logger.log('[Nuvio JS Error] $text');
        return null;
      });

      runtime.onMessage('nuvio_console_warn', (dynamic args) {
        final text = (args is Map && args['msg'] != null) ? args['msg'].toString() : args.toString();
        Logger.log('[Nuvio JS Warn] $text');
        return null;
      });

      if (code.contains("return { date: targetDate, title: targetTitle, dayIndex: dayIndex };")) {
        code = code.replaceAll(
          "return { date: targetDate, title: targetTitle, dayIndex: dayIndex };",
          "return { date: targetDate, title: targetTitle, showTitle: meta.name, dayIndex: dayIndex };",
        );
        code = code.replaceAll(
          "if (info.date) return { imdbId: id, releaseDate: info.date, episodeTitle: info.title, dayIndex: info.dayIndex, episode: episode };",
          "if (info.date) return { imdbId: id, releaseDate: info.date, title: info.showTitle || info.title, episodeTitle: info.title, dayIndex: info.dayIndex, episode: episode };",
        );
      }

      final hostPreamble = '''
async function __plugin_sleep(ms) { await new Promise(r => setTimeout(r, ms)); }
''';

      final fullScript = '''
$hostPreamble
${NuvioJsPolyfills.staticPolyfillCode}
var module = { exports: {} };
var exports = module.exports;
(function() {
$code
})();
${NuvioJsPolyfills.staticCallCode}
''';

      runtime.evaluate(fullScript);

      final jobTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        try {
          runtime.executePendingJob();
        } catch (_) {}
      });

      dynamic rawResult;
      try {
        rawResult = await resultCompleter.future.timeout(timeout, onTimeout: () => []);
      } finally {
        jobTimer.cancel();
      }
      dynamic decoded;
      if (rawResult is String) {
        try {
          decoded = jsonDecode(rawResult);
        } catch (_) {
          decoded = [];
        }
      } else {
        decoded = rawResult;
      }

      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => PluginRuntimeResult.fromJson(Map<String, dynamic>.from(m)))
            .where((r) => r.url.isNotEmpty || (r.infoHash != null && r.infoHash!.isNotEmpty))
            .toList();
      }
    } catch (e) {
      Logger.log('Error executing Nuvio scraper ($scraperId): $e');
    } finally {
      domBridge.clear();
      try {
        runtime.localContext.clear();
      } catch (_) {}
      try {
        runtime.evaluate('''
          if (typeof FLUTTER_NATIVEJS_PENDING_PROMISES !== 'undefined') {
            FLUTTER_NATIVEJS_PENDING_PROMISES = {};
          }
          delete globalThis.FLUTTER_NATIVEJS_PENDING_PROMISES;
          delete globalThis.FLUTTER_NATIVEJS_REGISTER_PROMISE;
          delete globalThis.FLUTTER_NATIVEJS_CLEAN_PROMISE;
          delete globalThis.FLUTTER_NATIVEJS_IS_PENDING_PROMISE;
          delete globalThis.FLUTTER_NATIVEJS_IS_FULLFILLED_PROMISE;
          delete globalThis.FLUTTER_NATIVEJS_IS_REJECTED_PROMISE;
          delete globalThis.FLUTTER_NATIVEJS_MakeQuerablePromise;
          delete globalThis.__get_scraper_id;
          delete globalThis.__get_scraper_settings;
          delete globalThis.__get_tmdb_api_key;
          delete globalThis.__get_call_args;
          delete globalThis.__capture_result;
          delete globalThis.__native_fetch;
          delete globalThis.__cheerio_load;
          delete globalThis.__cheerio_select;
          delete globalThis.__cheerio_find;
          delete globalThis.__cheerio_text;
          delete globalThis.__cheerio_inner_html;
          delete globalThis.__cheerio_html;
          delete globalThis.__cheerio_attr;
          delete globalThis.__cheerio_next;
          delete globalThis.__cheerio_prev;
          delete globalThis.__crypto_digest_hex_raw;
          delete globalThis.__crypto_hmac_hex_raw;
          delete globalThis.__crypto_pbkdf2_hex;
          delete globalThis.__crypto_aes_encrypt_hex;
          delete globalThis.__crypto_aes_decrypt_hex;
          delete globalThis.__crypto_get_random_values_hex;
          delete globalThis.__crypto_utf8_to_hex;
          delete globalThis.__crypto_hex_to_utf8;
          delete globalThis.__parse_url;
        ''');
      } catch (_) {}
      try {
        runZoned(
          () {
            runtime.dispose();
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) {
              if (line.contains('reference leak') || line.contains('JSError') || line.contains('QuickJsRuntime2') || line.contains('_JSFunction') || line.contains('FLUTTER_NATIVEJS')) {
                return;
              }
              parent.print(zone, line);
            },
          ),
        );
      } catch (_) {}
    }
    return [];
  }

  static Future<List<PluginSettingField>> getPluginSettingsLayout({
    required String code,
    required String scraperId,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final runtime = getJavascriptRuntime();
    final resultCompleter = Completer<dynamic>();

    try {
      final setToGlobal = runtime.evaluate("(key, val) => { this[key] = val; }").rawResult as JSInvokable;
      setToGlobal.invoke(['__get_scraper_id', () => scraperId]);
      setToGlobal.invoke(['__get_scraper_settings', () => "{}"]);
      setToGlobal.invoke(['__get_tmdb_api_key', () => ""]);
      setToGlobal.invoke(['__capture_result', (dynamic res) {
        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(res);
        }
      }]);
      _freeJs(setToGlobal);

      runtime.onMessage('nuvio_console_log', (dynamic args) => null);
      runtime.onMessage('nuvio_console_error', (dynamic args) => null);
      runtime.onMessage('nuvio_console_warn', (dynamic args) => null);

      final fullScript = '''
var module = { exports: {} };
var exports = module.exports;
(function() {
$code
})();
${NuvioJsPolyfills.staticSettingsCallCode}
''';

      runtime.evaluate(fullScript);

      final jobTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        try {
          runtime.executePendingJob();
        } catch (_) {}
      });

      dynamic rawResult;
      try {
        rawResult = await resultCompleter.future.timeout(timeout, onTimeout: () => []);
      } finally {
        jobTimer.cancel();
      }
      dynamic decoded;
      if (rawResult is String) {
        try {
          decoded = jsonDecode(rawResult);
        } catch (_) {
          decoded = [];
        }
      } else {
        decoded = rawResult;
      }

      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => PluginSettingField.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (e) {
      Logger.log('Error getting settings layout ($scraperId): $e');
    } finally {
      try {
        runtime.localContext.clear();
      } catch (_) {}
      try {
        runZoned(
          () {
            runtime.dispose();
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) {
              if (line.contains('reference leak') || line.contains('JSError') || line.contains('QuickJsRuntime2') || line.contains('_JSFunction') || line.contains('FLUTTER_NATIVEJS')) {
                return;
              }
              parent.print(zone, line);
            },
          ),
        );
      } catch (_) {}
    }
    return [];
  }
}
