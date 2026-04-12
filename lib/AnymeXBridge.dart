import 'dart:io';
import 'package:flutter/services.dart';
import 'Logger.dart';
import 'Settings/KvStore.dart';
import 'Runtime/RuntimeDownloader.dart';
import 'Runtime/Bridge/BridgeDispatcher.dart';
import 'Runtime/RuntimeController.dart';
import 'Runtime/RuntimePaths.dart';
import 'dart:async';



class AnymeXRuntimeBridge {
  static const _channel = MethodChannel('anymeXBridge');

  static bool get isSupportedPlatform => 
      Platform.isAndroid || Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Setup the AnymeX Runtime Bridge (Android APK or Desktop JRE/JAR).
  /// This handles downloading, tracking progress, and initialization.
  /// Set [force] to true to re-download the Bridge JAR/APK (useful for updates).
  /// Note: The JRE is only downloaded if missing, regardless of [force].
  static Future<void> setupRuntime(
      {String? customDownloadUrl,
      bool force = false,
      String? localApkPath}) async {
    if (!isSupportedPlatform) return;
    await RuntimeDownloader().setupRuntime(
        customUrl: customDownloadUrl, force: force, localApkPath: localApkPath);
  }

  /// Explicitly sets and loads a custom local APK. 
  /// This path is persisted and will be used automatically on future app restarts.
  static Future<bool> useLocalApk(String path) async {
    if (!Platform.isAndroid) return false;
    final exists = await File(path).exists();
    if (!exists) {
        Logger.log("useLocalApk: File does not exist at $path");
        return false;
    }
    
    try {
        setVal('runtime_host_path', path);
    } catch (e) {
        Logger.log('Failed to save runtime host APK path to KvStore: $e');
    }

    return await loadAnymeXRuntimeHost(path);
  }

  /// Checks if the runtime files already exist and initializes the bridge if they do.
  /// Call this on app startup to auto-load the bridge.
  static Future<void> checkAndInitialize() async {
    if (!isSupportedPlatform) return;

    final paths = RuntimePaths();
    
    String? savedPath;
    try {
        savedPath = getVal<String>('runtime_host_path');
    } catch (_) {}

    final bridgePath = (savedPath != null && await File(savedPath).exists())
        ? savedPath
        : await paths.bridgePath;
        
    final bridgeFile = File(bridgePath);
    bool exists = await bridgeFile.exists();

    if (!Platform.isAndroid) {
      final jreDir = await paths.jreDir;
      exists = exists && await jreDir.exists();
    }

    if (exists) {
      if (Platform.isAndroid) {
        await loadAnymeXRuntimeHost(bridgePath);
      } else {
        controller.setReady(true);
      }
      Logger.log("AnymeX Bridge auto-detected and initialized from: $bridgePath");
    }
  }


  static RuntimeController get controller => RuntimeController.it;

  static Completer<bool>? _loadCompleter;

  /// Standard MethodChannel call for Android only
  static Future<bool> loadAnymeXRuntimeHost(String apkPath,
      {Map<String, dynamic>? settings}) async {
    if (!Platform.isAndroid) return false;

    if (_loadCompleter != null) {
      Logger.log("AnymeX Bridge is already loading, waiting for completion...");
      return _loadCompleter!.future;
    }

    _loadCompleter = Completer<bool>();

    try {
      final result =
          await _channel.invokeMethod<bool>('loadAnymeXRuntimeHost', {
        'path': apkPath,
        if (settings != null) 'settings': settings,
      });
      final bool isLoaded = result ?? false;

      if (isLoaded) {
        try {
          setVal('runtime_host_path', apkPath);
        } catch (e) {
          Logger.log('Failed to save runtime host APK path to KvStore: $e');
        }
      }

      _loadCompleter!.complete(isLoaded);
      return isLoaded;
    } catch (e) {
      print('Failed to load Runtime Host APK from $apkPath: $e');
      _loadCompleter?.complete(false);
      return false;
    } finally {
      _loadCompleter = null;
    }
  }

  /// Checks if the AnymeXBridgeHost is already loaded into memory.
  static Future<bool> isLoaded() async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('isLoaded');
        return result ?? false;
      } catch (e) {
        return false;
      }
    }
    return controller.isReady.value;
  }

  /// Cancels an active request in the Runtime Host using its [token].
  static Future<bool> cancelRequest(String token) async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('cancelRequest', {
          'token': token,
        });
        return result ?? false;
      } catch (e) {
        print('Failed to cancel request for token $token: $e');
        return false;
      }
    } else {
      return await BridgeDispatcher().cancelRequest(token);
    }
  }
}
