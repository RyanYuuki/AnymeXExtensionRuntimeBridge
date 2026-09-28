import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

import '../../../Logger.dart';

class EmbeddedJvmBridge {
  static final EmbeddedJvmBridge _instance = EmbeddedJvmBridge._internal();
  factory EmbeddedJvmBridge() => _instance;
  EmbeddedJvmBridge._internal();

  static const _channel = MethodChannel(
    'anymex_extension_bridge/embedded_jvm',
  );

  static Future<void>? _vmStart;
  String? _jarPath;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> init({required String pluginJarPath}) async {
    if (_loaded) return;
    _jarPath = pluginJarPath;

    await (_vmStart ??= _channel.invokeMethod<void>('start').catchError((Object e) {
      _vmStart = null;
      throw e;
    }));

    await _channel.invokeMethod<void>('load', {'jarPath': pluginJarPath});
    _loaded = true;
    Logger.log('Embedded JVM: loaded $pluginJarPath');
  }

  Future<dynamic> invokeMethod(
    String method,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!_loaded || _jarPath == null) {
      throw Exception('Embedded JVM bridge not initialized');
    }

    try {
      final envelope = await _channel.invokeMethod<String>('call', {
        'jarPath': _jarPath,
        'request': jsonEncode({'method': method, 'args': args}),
      }).timeout(timeout);

      final decodedEnvelope =
          jsonDecode(envelope ?? '{}') as Map<String, dynamic>;

      if (decodedEnvelope['success'] != true) {
        throw Exception(
          decodedEnvelope['error']?.toString() ?? 'Embedded JVM call failed',
        );
      }

      final data = decodedEnvelope['data'];
      return data is String ? jsonDecode(data) : data;
    } catch (e, s) {
      Logger.log('[EMBEDDED-JVM] Call failed: $e\n$s', show: true);
      rethrow;
    }
  }

  void dispose() {
    _loaded = false;
    final jar = _jarPath;
    _jarPath = null;
    if (jar == null) return;
    unawaited(
      _channel.invokeMethod<void>('unload', {'jarPath': jar}).catchError((_) {}),
    );
  }
}
