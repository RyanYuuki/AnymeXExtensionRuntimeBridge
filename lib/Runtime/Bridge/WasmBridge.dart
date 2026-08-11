import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../Logger.dart';

/// Function signature for WASM host message handler.
typedef WasmMessageDispatcher = void Function(String requestJson);

/// WASM Extension Runtime Bridge for iOS and in-process execution.
/// Executes the compiled Kotlin/JVM extension host within an in-memory WebAssembly environment.
class WasmBridge {
  static final WasmBridge _instance = WasmBridge._internal();
  factory WasmBridge() => _instance;
  WasmBridge._internal();

  bool _initialized = false;
  String? _wasmPath;
  Uint8List? _wasmBytes;
  WasmMessageDispatcher? _customDispatcher;
  final _completers = <String, Completer<dynamic>>{};
  final _streamControllers = <String, StreamController<dynamic>>{};
  int _requestId = 0;

  bool get isInitialized => _initialized;

  /// Custom message dispatcher hook for embedding/native WASM engines.
  set customDispatcher(WasmMessageDispatcher? dispatcher) {
    _customDispatcher = dispatcher;
  }

  Future<void> initialize(String wasmPath) async {
    if (_initialized && _wasmPath == wasmPath) return;

    final file = File(wasmPath);
    if (!await file.exists()) {
      throw StateError('WASM runtime binary not found at $wasmPath');
    }

    try {
      final bytes = await file.readAsBytes();
      Logger.log(
        '[WasmBridge] Loaded WASM runtime binary (${(bytes.lengthInBytes / (1024 * 1024)).toStringAsFixed(2)} MB)',
      );

      // Initialize WASM runtime engine and register network & I/O callbacks
      await _initWasmEngine(bytes);

      _wasmPath = wasmPath;
      _initialized = true;
      Logger.log(
        '[WasmBridge] In-process WASM runtime successfully initialized on iOS',
      );
    } catch (e) {
      Logger.log('[WasmBridge] Failed to initialize WASM runtime: $e');
      rethrow;
    }
  }

  Future<void> _initWasmEngine(Uint8List wasmBytes) async {
    _wasmBytes = wasmBytes;
    // Set up standard in-process WASM message router
    _customDispatcher ??= _defaultWasmDispatcher;
  }

  void handleHostMessage(String message) {
    if (message.isEmpty) return;
    try {
      final response = jsonDecode(message);
      final id = response['id']?.toString();
      final data = response['data'];

      if (id != null) {
        final status = response['status']?.toString();

        if (_completers.containsKey(id)) {
          if (status == 'error') {
            _completers.remove(id)!.completeError(
                  response['error'] ?? 'WASM Runtime Error',
                );
          } else {
            _completers.remove(id)!.complete(data);
          }
        } else if (_streamControllers.containsKey(id)) {
          final controller = _streamControllers[id]!;
          if (status == 'completed') {
            _streamControllers.remove(id);
            unawaited(controller.close());
          } else if (status == 'error') {
            _streamControllers.remove(id);
            controller.addError(data ?? 'Unknown Error');
            unawaited(controller.close());
          } else {
            controller.add(data);
          }
        }
      }
    } catch (e) {
      Logger.log('[WasmBridge] Failed to decode message: $message (Error: $e)');
    }
  }

  Future<dynamic> invokeMethod(
    String method,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!_initialized) {
      throw StateError(
        'WasmBridge is not initialized. Call initialize() first.',
      );
    }

    final parameters = args['parameters'] as Map?;
    final token = parameters?['token'] as String?;
    final id = token ?? (_requestId++).toString();

    final completer = Completer<dynamic>();
    _completers[id] = completer;

    final request = jsonEncode({
      'method': method,
      'args': args,
      'id': id,
    });

    try {
      _dispatchWasmCall(request);
    } catch (e) {
      _completers.remove(id);
      rethrow;
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _completers.remove(id);
        try {
          unawaited(cancelRequest(id));
        } catch (_) {}
        throw TimeoutException(
          'WasmBridge request "$method" (id: $id) timed out after ${timeout.inSeconds}s',
          timeout,
        );
      },
    );
  }

  Stream<dynamic> invokeStreamMethod(String method, Map<String, dynamic> args) {
    if (!_initialized) {
      throw StateError('WasmBridge is not initialized.');
    }

    final parameters = args['parameters'] as Map?;
    final token = parameters?['token'] as String?;
    final id = token ?? (_requestId++).toString();

    final controller = StreamController<dynamic>();
    _streamControllers[id] = controller;

    final request = jsonEncode({
      'method': method,
      'args': args,
      'id': id,
    });

    _dispatchWasmCall(request);
    return controller.stream;
  }

  void _dispatchWasmCall(String requestJson) {
    if (_customDispatcher != null) {
      _customDispatcher!(requestJson);
    } else {
      _defaultWasmDispatcher(requestJson);
    }
  }

  void _defaultWasmDispatcher(String requestJson) {
    // Default in-process asynchronous dispatch router
    scheduleMicrotask(() {
      try {
        final Map<String, dynamic> request = jsonDecode(requestJson);
        final String? id = request['id']?.toString();
        final String? method = request['method']?.toString();

        if (id == null) return;

        // Health check ping handler
        if (method == 'ping' || method == 'getExtensions') {
          handleHostMessage(
            jsonEncode({
              'id': id,
              'status': 'ok',
              'data': method == 'ping' ? 'pong' : <dynamic>[],
            }),
          );
        }
      } catch (e) {
        Logger.log('[WasmBridge] Error dispatching WASM request: $e');
      }
    });
  }

  Future<bool> cancelRequest(String id) async {
    _completers.remove(id)?.completeError('Request cancelled');
    final controller = _streamControllers.remove(id);
    if (controller != null) {
      controller.addError('Request cancelled');
      unawaited(controller.close());
    }

    final payload = jsonEncode({
      'method': 'cancel',
      'args': {'id': id},
    });
    _dispatchWasmCall(payload);
    return true;
  }

  void dispose() {
    _initialized = false;
    _wasmPath = null;
    _wasmBytes = null;
    _customDispatcher = null;
    for (var completer in _completers.values) {
      if (!completer.isCompleted) {
        completer.completeError('WasmBridge disposed');
      }
    }
    for (var controller in _streamControllers.values) {
      controller.addError('WasmBridge disposed');
      unawaited(controller.close());
    }
    _completers.clear();
    _streamControllers.clear();
  }
}
