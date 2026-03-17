import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'Logger.dart';
import 'Settings/KvStore.dart';

class AnymeXRuntimeBridge {
  static const _channel = MethodChannel('anymeXBridge');

  static bool get _isSupportedPlatform => Platform.isAndroid;

  /// Loads the Runtime Host APK from the given [apkPath].
  /// This must be called (and must return true) before any Aniyomi or CloudStream
  /// extension methods are invoked.
  /// also gang if it throws error, then try using loadRuntimeHostFromPicker or pick a app sandbox path
  static Future<bool> loadAnymeXRuntimeHost(String apkPath) async {
    if (!_isSupportedPlatform) return false;

    try {
      final result =
          await _channel.invokeMethod<bool>('loadAnymeXRuntimeHost', {
        'path': apkPath,
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
    if (!_isSupportedPlatform) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isLoaded');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Opens a file picker for the user to select the Runtime Host APK.
  /// If selected, copies it to the app's document directory and loads it.
  static Future<bool> loadRuntimeHostFromPicker() async {
    if (!_isSupportedPlatform) return false;

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['apk'],
      );

      if (result != null && result.files.single.path != null) {
        final String originalPath = result.files.single.path!;
        final Directory appDocDir = await getApplicationDocumentsDirectory();

        final String targetPath = '${appDocDir.path}/runtime_host.apk';
        final File originalFile = File(originalPath);
        await originalFile.copy(targetPath);

        return await loadAnymeXRuntimeHost(targetPath);
      }
      return false;
    } catch (e) {
      print('Error picking or loading APK: $e');
      return false;
    }
  }
}
