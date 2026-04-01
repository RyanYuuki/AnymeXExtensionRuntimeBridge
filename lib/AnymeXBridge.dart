import 'dart:io';
import 'package:flutter/services.dart';
import 'Logger.dart';
import 'Settings/KvStore.dart';
import 'Services/Runtime/RuntimeDownloader.dart';
import 'Services/Runtime/RuntimeController.dart';
import 'Services/Runtime/RuntimePaths.dart';


class AnymeXRuntimeBridge {
  static const _channel = MethodChannel('anymeXBridge');

  static bool get isSupportedPlatform => 
      Platform.isAndroid || Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Setup the AnymeX Runtime Bridge (Android APK or Desktop JRE/JAR).
  /// This handles downloading, tracking progress, and initialization.
  /// Set [force] to true to re-download the Bridge JAR/APK (useful for updates).
  /// Note: The JRE is only downloaded if missing, regardless of [force].
  static Future<void> setupRuntime({String? customDownloadUrl, bool force = false, String? localApkPath}) async {
    if (!isSupportedPlatform) return;
    await RuntimeDownloader().setupRuntime(customUrl: customDownloadUrl, force: force, localApkPath: localApkPath);
  }

  /// Checks if the runtime files already exist and initializes the bridge if they do.
  /// Call this on app startup to auto-load the bridge.
  static Future<void> checkAndInitialize() async {
    if (!isSupportedPlatform) return;
    
    final paths = RuntimePaths();
    final bridgePath = await paths.bridgePath;
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
      Logger.log("AnymeX Bridge auto-detected and initialized.");
    }
  }

  /// Reactive controller for UI setup status and progress
  static RuntimeController get controller => RuntimeController.it;

  /// Standard MethodChannel call for Android only
  static Future<bool> loadAnymeXRuntimeHost(String apkPath,
      {Map<String, dynamic>? settings}) async {
    if (!Platform.isAndroid) return false;

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

      return isLoaded;
    } catch (e) {
      print('Failed to load Runtime Host APK from $apkPath: $e');
      return false;
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
    }
    return false; 
  }
}
