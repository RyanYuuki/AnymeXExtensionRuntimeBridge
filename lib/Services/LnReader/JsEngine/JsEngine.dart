import 'dart:async';
import 'dart:convert';

import 'package:flutter_qjs/flutter_qjs.dart';

import '../../JsEngine.dart';

class JsExtensionEngine {
  JsExtensionEngine._internal();
  static final JsExtensionEngine instance = JsExtensionEngine._internal();

  late final JavascriptRuntime _runtime;
  Completer<void>? _initCompleter;

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

      _runtime.onMessage('bridge', (dynamic args) async {
        // final data = args;

        /* if (data is Map && data['type'] == 'fetchv2') {
            return fetch.handle(data);
          }*/

        throw Exception('Unknown bridge call');
      });

      // Shimming fjs.bridge_call for compatibility
      _runtime.evaluate('''
        var fjs = {
          bridge_call: function(data) {
            return sendMessage('bridge', data);
          }
        };
      ''');

      _initCompleter?.complete();
    } catch (e, stack) {
      _initCompleter?.completeError(e, stack);
      _initCompleter = null;
    }
  }

  Future<void> loadModule({
    required String moduleName,
    required String sourceCode,
  }) async {
    await init();

    final wrapped = '''
$sourceCode

globalThis['$moduleName'] = exports.default ?? exports;
''';

    _runtime.evaluate(wrapped);
  }

  Future<dynamic> call({
    required String moduleName,
    required String method,
    List<dynamic> params = const [],
  }) async {
    await init();

    final encodedParams = jsonEncode(params);

    final js = '''
    (async () => {
      const target = globalThis['$moduleName'];

      if (!target)
        throw new Error("Module '$moduleName' not found");

      const fn = target["$method"];

      if (typeof fn !== "function")
        throw new Error("Method '$method' not found");

      const args = JSON.parse('$encodedParams');
      return await fn(...args);
    })()
    ''';

    final result =
        await _runtime.handlePromise(await _runtime.evaluateAsync(js));
    return result;
  }

  Future<void> dispose() async {
    _initCompleter = null;
  }
}
