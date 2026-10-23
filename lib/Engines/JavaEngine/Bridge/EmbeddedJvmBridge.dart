import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../Logger.dart';

class EmbeddedJvmBridge {
  static final EmbeddedJvmBridge _instance = EmbeddedJvmBridge._internal();
  factory EmbeddedJvmBridge() => _instance;
  EmbeddedJvmBridge._internal();

  static const _channel = MethodChannel(
    'anymex_extension_bridge/embedded_jvm',
  );

  static Future<void>? _vmStart;
  static bool _listeningForLogs = false;

  String? _jarPath;
  bool _loaded = false;

  static const _crashWindow = Duration(days: 3);
  static const _reportLines = 300;

  bool get isLoaded => _loaded;

  static void _listenForLogs() {
    if (_listeningForLogs) return;
    _listeningForLogs = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'log') return;
      for (final line in (call.arguments as List? ?? const [])) {
        Logger.log('[JVM] $line');
      }
    });
  }

  static Future<File> _crashFlag() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/embedded_jvm_start.flag');
  }

  static Future<void> clearCrashFlag() async {
    final flag = await _crashFlag();
    if (await flag.exists()) await flag.delete();
  }

  static Future<String?> _prepareLogDirectory() async {
    try {
      final baseDir = await getApplicationSupportDirectory();
      final dir = Directory('${baseDir.path}/JvmLogs');
      await dir.create(recursive: true);

      final current = File('${dir.path}/jvm.log');
      if (await current.exists()) {
        await current.rename('${dir.path}/jvm.previous.log');
      }

      final errorReport = File('${dir.path}/hs_err.log');
      if (await errorReport.exists()) {
        Logger.log(
          '[JVM] Fatal error report (${errorReport.path}):\n'
          '${await _head(errorReport, _reportLines)}',
          show: true,
        );
        await errorReport.rename('${dir.path}/hs_err.previous.log');
      }

      Logger.log('[JVM] Logging to ${current.path}');
      return dir.path;
    } catch (e) {
      Logger.log('[JVM] Could not prepare the log directory: $e');
      return null;
    }
  }

  static Future<String> _head(File file, int lines) async {
    final all = await file.readAsLines().catchError((_) => <String>[]);
    return all.take(lines).join('\n');
  }

  static Future<String> _tail(File file, int lines) async {
    if (!await file.exists()) return '(no log)';
    final all = await file.readAsLines().catchError((_) => <String>[]);
    return all.skip(all.length > lines ? all.length - lines : 0).join('\n');
  }

  static Future<void> _startVm() async {
    _listenForLogs();
    final logDirectory = await _prepareLogDirectory();

    final flag = await _crashFlag();
    if (await flag.exists()) {
      final started = DateTime.tryParse(await flag.readAsString());
      if (started != null &&
          DateTime.now().difference(started) < _crashWindow) {
        if (logDirectory != null) {
          Logger.log(
            '[JVM] The last start closed the app. Its final log lines:\n'
            '${await _tail(File('$logDirectory/jvm.previous.log'), _reportLines)}',
            show: true,
          );
        }
        throw Exception(
          'The embedded Java runtime closed the app the last time it started '
          'on this device, so it is turned off. Java based sources are '
          'unavailable here.',
        );
      }
    }

    final watch = Stopwatch()..start();
    Logger.log('[JVM] Starting the embedded Java runtime');
    await flag.writeAsString(DateTime.now().toIso8601String(), flush: true);
    try {
      await _channel.invokeMethod<void>('start', {
        if (logDirectory != null) 'logDirectory': logDirectory,
      });
    } catch (e) {
      Logger.log('[JVM] Start failed after ${watch.elapsedMilliseconds} ms: $e',
          show: true);
      if (await flag.exists()) await flag.delete();
      rethrow;
    }
    if (await flag.exists()) await flag.delete();
    Logger.log('[JVM] Runtime up in ${watch.elapsedMilliseconds} ms');
  }

  Future<void> init({required String pluginJarPath}) async {
    if (_loaded) return;
    _jarPath = pluginJarPath;

    await (_vmStart ??= _startVm().catchError((Object e) {
      _vmStart = null;
      throw e;
    }));

    final watch = Stopwatch()..start();
    try {
      await _channel.invokeMethod<void>('load', {'jarPath': pluginJarPath});
    } catch (e) {
      Logger.log('[JVM] Loading $pluginJarPath failed: $e', show: true);
      rethrow;
    }
    _loaded = true;
    Logger.log(
      '[JVM] Loaded $pluginJarPath in ${watch.elapsedMilliseconds} ms',
    );
  }

  Future<dynamic> invokeMethod(
    String method,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (!_loaded || _jarPath == null) {
      throw Exception('Embedded JVM bridge not initialized');
    }

    final label = _label(method, args);
    final watch = Stopwatch()..start();
    try {
      final envelope = await _channel.invokeMethod<String>('call', {
        'jarPath': _jarPath,
        'request': jsonEncode({'method': method, 'args': args}),
      }).timeout(timeout);

      final decodedEnvelope =
          jsonDecode(envelope ?? '{}') as Map<String, dynamic>;

      if (decodedEnvelope['success'] != true) {
        final trace = decodedEnvelope['trace'];
        throw _EmbeddedJvmCallError(
          decodedEnvelope['error']?.toString() ?? 'Embedded JVM call failed',
          trace is String ? trace : null,
        );
      }

      final data = decodedEnvelope['data'];
      dynamic decoded;
      if (data is String) {
        try {
          decoded = jsonDecode(data);
        } catch (_) {
          decoded = data;
        }
      } else {
        decoded = data;
      }
      Logger.log('[JVM] $label ok in ${watch.elapsedMilliseconds} ms');
      return decoded;
    } catch (e, s) {
      final detail = e is _EmbeddedJvmCallError && e.trace != null
          ? '\n${e.trace}'
          : '\n$s';
      Logger.log(
        '[JVM] $label failed after ${watch.elapsedMilliseconds} ms: $e$detail',
        show: true,
      );
      rethrow;
    }
  }

  String _label(String method, Map<String, dynamic>? args) {
    final name = _jarPath?.split('/').last ?? '?';
    final source = args?['sourceId'];
    return source == null ? '$name $method' : '$name $method (source $source)';
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

class _EmbeddedJvmCallError implements Exception {
  final String message;
  final String? trace;

  _EmbeddedJvmCallError(this.message, this.trace);

  @override
  String toString() => message;
}
