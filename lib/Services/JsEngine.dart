import 'dart:async';

import 'package:flutter_qjs/flutter_qjs.dart';

class JsEngineEnv {
  JsEngineEnv._internal();
  static final JsEngineEnv instance = JsEngineEnv._internal();

  late final JavascriptRuntime _runtime;

  Completer<JavascriptRuntime>? _runtimeCompleter;

  Future<JavascriptRuntime> init() {
    if (_runtimeCompleter != null) {
      return _runtimeCompleter!.future;
    }

    _runtimeCompleter = Completer<JavascriptRuntime>();
    _doInit();
    return _runtimeCompleter!.future;
  }

  Future<void> _doInit() async {
    try {
      _runtime = QuickJsRuntime2(stackSize: 1024 * 1024 * 4);
      _runtime.enableHandlePromises();

      _runtimeCompleter?.complete(_runtime);
    } catch (e, stack) {
      _runtimeCompleter?.completeError(e, stack);
      _runtimeCompleter = null;
    }
  }

  JavascriptRuntime get runtime {
    if (_runtimeCompleter == null || !_runtimeCompleter!.isCompleted) {
      throw StateError('JsExtensionEngine not initialized. Call init() first.');
    }
    return _runtime;
  }

  Future<void> dispose() async {
    if (_runtimeCompleter == null) return;

    _runtime.dispose();
    _runtimeCompleter = null;
  }
}
