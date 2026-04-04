import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../Runtime/RuntimePaths.dart';

class SidecarBridge {
  static final SidecarBridge _instance = SidecarBridge._internal();
  factory SidecarBridge() => _instance;
  SidecarBridge._internal();

  Process? _process;
  bool _initialized = false;
  final _completers = <String, Completer<dynamic>>{};
  int _requestId = 0;

  Future<void> initialize(String bridgeJarPath) async {
    if (_initialized) return;

    final paths = RuntimePaths();
    final javaPath = await paths.javaExecutablePath;

    if (javaPath == null) {
      throw StateError(
          'Java executable not found. Please ensure JRE is installed.');
    }

    final completer = Completer<void>();

    print('Starting Sidecar Process: $javaPath -jar $bridgeJarPath');
    
    _process = await Process.start(javaPath, ['-jar', bridgeJarPath]);

    _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleResponse);

    _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      print('[Sidecar Log] $line');
      if (line.contains("AnymeX Sidecar Process Started") && !completer.isCompleted) {
        completer.complete();
      }
    });

    await completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
      if (!completer.isCompleted) {
        print('[Sidecar] Warning: Startup signal not received, continuing anyway...');
        completer.complete();
      }
    });

    _initialized = true;
  }

  void _handleResponse(String line) {
    if (line.isEmpty) return;
    try {
      final response = jsonDecode(line);
      final id = response['id']?.toString();
      final data = response['data'];

      if (id != null && _completers.containsKey(id)) {
        _completers.remove(id)!.complete(data);
      }
    } catch (e) {
      print('[Sidecar] Failed to decode response: $line');
    }
  }

  Future<dynamic> invokeMethod(String method, Map<String, dynamic> args) async {
    if (!_initialized || _process == null) {
      throw StateError('SidecarBridge is not initialized.');
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

    _process!.stdin.writeln(request);
    
    return completer.future;
  }

  void dispose() {
    _process?.kill();
    _process = null;
    _initialized = false;
    for (var completer in _completers.values) {
      if (!completer.isCompleted) {
        completer.completeError('Bridge disposed');
      }
    }
    _completers.clear();
  }

  Future<bool> cancelRequest(String id) async {
    if (_process == null) return false;
    
    _completers.remove(id)?.completeError('Request cancelled');
    
    print('[Sidecar Log] [DART] Requesting CANCEL for ID: $id');
    
    final payload = jsonEncode({
      'method': 'cancel',
      'args': {'id': id},
    });
    _process!.stdin.writeln(payload);
    print('[Sidecar] Sent cancel request for ID: $id');
    return true;
  }
}
