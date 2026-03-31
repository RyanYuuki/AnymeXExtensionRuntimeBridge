import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:http/http.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'AnymeXBridge.dart';
import 'ExtensionManager.dart';
import 'Logger.dart';
import 'Services/LnReader/JsEngine/JsEngine.dart';
import 'Settings/KvStore.dart';

Isar isar = AnymeXExtensionBridge.isar;

class AnymeXExtensionBridge {
  AnymeXExtensionBridge._();

  static late final BridgeContext context;
  static bool _initialized = false;
  static String projectName = 'AnymeX';

  /// A safe default [GetDirectory] implementation using `path_provider`.
  ///
  /// By default, it stores data under [getApplicationSupportDirectory] in a
  /// folder named [appFolderName]. If [useCustomPath] is `true`, it uses
  /// [getApplicationDocumentsDirectory] instead (useful when you want user-
  /// visible files on desktop/mobile).
  ///
  /// If you pass [baseDirectory], it will be used as the base for [subPath].
  static GetDirectory defaultGetDirectory({
    Directory? baseDirectory,
    String appFolderName = 'AnymeXExtensionBridge',
  }) {
    return ({
      String? subPath,
      bool useCustomPath = false,
      bool useSystemPath = false,
    }) async {
      final Directory base;
      if (baseDirectory != null) {
        base = baseDirectory;
      } else if (useCustomPath && !useSystemPath) {
        base = await getApplicationDocumentsDirectory();
      } else {
        base = await getApplicationSupportDirectory();
      }

      final Directory root = Directory(p.join(base.path, appFolderName));
      final Directory dir =
          subPath == null ? root : Directory(p.join(root.path, subPath));

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      return dir;
    };
  }

  /// Initializes the AnymeX Extension Bridge.
  ///
  /// [getDirectory] is required to resolve directories for Isar and WebView data.
  /// {@macro get_directory_contract}
  ///
  /// [http] is an optional HTTP client for network requests.
  ///
  /// [isarInstance] provides your Isar client and must include [isarSchema].
  /// If omitted, a new instance will be initialized internally.
  static Future<void> init({
    required GetDirectory getDirectory,
    Client? http,
    Isar? isarInstance,
    String? projectName,
  }) async {
    if (_initialized) return;

    if (projectName != null) {
      AnymeXExtensionBridge.projectName = projectName;
    }

    Logger.init();

    final isar = isarInstance ?? await _openIsar(getDirectory);

    final webViewEnv =
        Platform.isWindows ? await _createWebViewEnv(getDirectory) : null;

    context = BridgeContext(
      isar: isar,
      http: http,
      webViewEnvironment: webViewEnv,
      getDirectory: getDirectory,
    );

    Get.lazyPut<ExtensionManager>(() => ExtensionManager());
    _initialized = true;

    final apkPath = getVal<String>('runtime_host_path');
    if (apkPath != null) {
      await AnymeXRuntimeBridge.loadAnymeXRuntimeHost(apkPath);
    }
  }

  static Future<Isar> _openIsar(GetDirectory getDirectory) async {
    final dir = await getDirectory(
      subPath: 'isar',
      useSystemPath: true,
      useCustomPath: false,
    );

    if (dir == null) {
      throw StateError('Isar directory could not be resolved');
    }

    if (dir.path.trim().isEmpty) {
      throw StateError(
        'Isar directory resolved to an empty path. '
        'Ensure your getDirectory() returns a Directory with a valid, writable path.',
      );
    }

    if (!p.isAbsolute(dir.path)) {
      throw StateError(
          'Isar directory must be an absolute path; got: "${dir.path}". '
          'If you built it via string interpolation, use Directory(path.join(base.path, subPath)) ');
    }

    return Isar.open(
      isarSchema,
      directory: dir.path,
    );
  }

  static Future<WebViewEnvironment?> _createWebViewEnv(
    GetDirectory getDirectory,
  ) async {
    final version = await WebViewEnvironment.getAvailableVersion();
    if (version == null) return null;

    final dir = await getDirectory(
      subPath: 'webview',
      useSystemPath: true,
      useCustomPath: false,
    );

    if (dir == null) return null;
    if (dir.path.trim().isEmpty) return null;
    if (!p.isAbsolute(dir.path)) return null;

    return WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: dir.path,
      ),
    );
  }

  static void _assertInitialized() {
    if (!_initialized) {
      throw StateError(
        'AnymeXExtensionBridge.init() must be called first',
      );
    }
  }

  static Isar get isar {
    _assertInitialized();
    return context.isar;
  }

  static const isarSchema = [
    KvEntrySchema,
  ];

  static void Function(String log, bool show) onLog = (log, _) {
    debugPrint('AnymeXExtensionBridge: $log');
  };

  static void dispose() {
    if (_initialized) {
      _initialized = false;
      JsExtensionEngine.instance.dispose();
    }
  }
}

/// {@macro get_directory_contract}
typedef GetDirectory = Future<Directory?> Function({
  String? subPath,
  bool useCustomPath,
  bool useSystemPath,
});

class BridgeContext {
  final Isar isar;
  final Client? http;
  final WebViewEnvironment? webViewEnvironment;
  final GetDirectory getDirectory;

  const BridgeContext({
    required this.isar,
    this.http,
    this.webViewEnvironment,
    required this.getDirectory,
  });

  /// Only for android platform, dont calll this shit if you're on other platforms
  Future<Directory?> getCloudStreamPluginDirectory() async {
    if (!Platform.isAndroid) return null;
    return await getDirectory(
      subPath: 'cloudstream_plugins',
      useCustomPath: true,
      useSystemPath: false,
    );
  }
}

/// {@template get_directory_contract}
/// Resolves directories used by the AnymeX Extension Bridge.
///
/// Implementations must:
/// - Return a stable, persistent directory
/// - Create the directory if it does not exist
/// - Respect `subPath`, `useCustomPath`, and `useSystemPath`
///
/// ### Example
///
/// ```dart
/// Future<Directory?> getDirectory({
///   String? subPath,
///   bool useCustomPath = false,
///   bool useSystemPath = false,
/// }) async {
///   final base = await getApplicationSupportDirectory();
///   final dir = subPath != null
///       ? Directory('${base.path}/$subPath')
///       : base;
///
///   if (!await dir.exists()) {
///     await dir.create(recursive: true);
///   }
///
///   return dir;
/// }
/// ```
/// {@endtemplate}
