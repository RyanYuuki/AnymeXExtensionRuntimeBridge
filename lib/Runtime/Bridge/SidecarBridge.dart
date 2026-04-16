import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../RuntimePaths.dart';

class SidecarBridge {
  static final SidecarBridge _instance = SidecarBridge._internal();
  factory SidecarBridge() => _instance;
  SidecarBridge._internal();

  Process? _process;
  bool _initialized = false;
  final _completers = <String, Completer<dynamic>>{};
  final _streamControllers = <String, StreamController<dynamic>>{};
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
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_handleResponse);

    _process!.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
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

      if (id != null) {
        final status = response['status']?.toString();
        
        if (_completers.containsKey(id)) {
           if (status == 'partial') {
            print('yeah no idea what to do with this one');
           } else {
             _completers.remove(id)!.complete(data);
           }
        } else if (_streamControllers.containsKey(id)) {
           final controller = _streamControllers[id]!;
           if (status == 'completed') {
             _streamControllers.remove(id)!.close();
           } else if (status == 'error') {
             _streamControllers.remove(id)!.addError(data ?? 'Unknown Error');
           } else {
             controller.add(data);
           }
        }
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

  Stream<dynamic> invokeStreamMethod(String method, Map<String, dynamic> args) {
    if (!_initialized || _process == null) {
      throw StateError('SidecarBridge is not initialized.');
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

    _process!.stdin.writeln(request);

    return controller.stream;
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
    for (var controller in _streamControllers.values) {
      controller.addError('Bridge disposed');
      controller.close();
    }
    _completers.clear();
    _streamControllers.clear();
  }

  Future<bool> cancelRequest(String id) async {
    if (_process == null) return false;
    
    _completers.remove(id)?.completeError('Request cancelled');
    _streamControllers.remove(id)?.addError('Request cancelled');
    _streamControllers.remove(id)?.close();
    
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
