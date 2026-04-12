import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:jni/jni.dart';
import '../RuntimePaths.dart';
import '../../Native/AnymeXNativeBindings.dart';

class JniBridge {
  static final JniBridge _instance = JniBridge._internal();
  factory JniBridge() => _instance;
  JniBridge._internal();

  bool _initialized = false;
  String? _bridgeJarPath;

  static void _setupDylibDir() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    if (Platform.isWindows) {
      Jni.setDylibDir(dylibDir:  exeDir);
    } else if (Platform.isLinux) {
      Jni.setDylibDir(dylibDir:  p.join(exeDir, 'lib'));
    }
  }

  Future<void> initialize(String bridgeJarPath) async {
    if (_initialized) return;
    _bridgeJarPath = bridgeJarPath;

    final paths = RuntimePaths();
    final jvmPath = await paths.jvmLibPath;

    if (jvmPath == null) {
      throw StateError(
          'JVM library not found. Please ensure JRE is installed via RuntimeDownloader.');
    }

    try {
      ffi.DynamicLibrary.open(jvmPath);
    } catch (e) {
      print('Warning: Failed to preload JVM library at $jvmPath: $e');
    }

    _setupDylibDir();
    
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final jniJarPath = Platform.isWindows ? p.join(exeDir, 'jni.jar') : p.join(exeDir, 'lib', 'jni.jar');

    Jni.spawnIfNotExists(
      classPath: [bridgeJarPath, jniJarPath],
    );

    _initialized = true;
    print('JNI Bridge initialized with $bridgeJarPath using JVM: $jvmPath');
  }

  Future<dynamic> invokeMethod(String method, Map<String, dynamic> args) async {
    if (!_initialized || _bridgeJarPath == null) {
      throw StateError(
          'JniBridge is not initialized. Call initialize() first.');
    }

    final String bridgeJarPath = _bridgeJarPath!;
    final paths = RuntimePaths();
    final String? jvmPath = await paths.jvmLibPath;

    return await Isolate.run(() async {
      if (jvmPath != null) {
        try {
          ffi.DynamicLibrary.open(jvmPath);
        } catch (e) {}
      }

      _setupDylibDir();
      
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final jniJarPath = Platform.isWindows ? p.join(exeDir, 'jni.jar') : p.join(exeDir, 'lib', 'jni.jar');

      Jni.spawnIfNotExists(
        classPath: [bridgeJarPath, jniJarPath],
      );

      return await using((arena) async {
        switch (method) {
          case 'loadExtensions':
            final folderPath = args['folderPath'] as String;
            final jsonString = AniyomiSourceMethods.INSTANCE.loadExtensions(
              folderPath.toJString()..releasedBy(arena),
            ).toDartString(releaseOriginal: true);
            return jsonDecode(jsonString);

          case 'getPopular':
          case 'getLatestUpdates':
            final isPopular = method == 'getPopular';
            final sourceId = (args['sourceId'] as String).toJString()..releasedBy(arena);
            final page = args['page'] as int;
            final isAnime = args['isAnime'] as bool;

            final JString jsonJString;
            if (isPopular) {
              jsonJString = await AniyomiSourceMethods.INSTANCE.fetchPopular(
                sourceId,
                page,
                isAnime.toJBoolean()..releasedBy(arena),
              );
            } else {
              jsonJString = await AniyomiSourceMethods.INSTANCE.fetchLatestUpdates(
                sourceId,
                page,
                isAnime.toJBoolean()..releasedBy(arena),
              );
            }
            return jsonDecode(jsonJString.toDartString(releaseOriginal: true));

          case 'search':
            final sourceId = (args['sourceId'] as String).toJString()..releasedBy(arena);
            final query = (args['query'] as String).toJString()..releasedBy(arena);
            final page = args['page'] as int;
            final isAnime = args['isAnime'] as bool;

            final jsonJString = await AniyomiSourceMethods.INSTANCE.search(
              sourceId,
              query,
              page,
              isAnime.toJBoolean()..releasedBy(arena),
            );
            return jsonDecode(jsonJString.toDartString(releaseOriginal: true));

          case 'getDetail':
            final sourceId = (args['sourceId'] as String).toJString()..releasedBy(arena);
            final mediaMap = args['media'] as Map;
            final url = (mediaMap['url'] as String? ?? '').toJString()..releasedBy(arena);
            final title = (mediaMap['title'] as String? ?? '').toJString()..releasedBy(arena);
            final cover = (mediaMap['thumbnail_url'] as String? ?? '').toJString()..releasedBy(arena);
            final isAnime = args['isAnime'] as bool;

            final jsonJString = await AniyomiSourceMethods.INSTANCE.fetchDetails(
              sourceId,
              url,
              title,
              cover,
              isAnime.toJBoolean()..releasedBy(arena),
            );
            return jsonDecode(jsonJString.toDartString(releaseOriginal: true));

          case 'getVideoList':
            final sourceId = (args['sourceId'] as String).toJString()..releasedBy(arena);
            final epMap = args['episode'] as Map;
            final url = (epMap['url'] as String? ?? '').toJString()..releasedBy(arena);
            final name = (epMap['name'] as String? ?? '').toJString()..releasedBy(arena);

            final jsonJString = await AniyomiSourceMethods.INSTANCE.fetchVideoList(
              sourceId,
              url,
              name,
            );
            return jsonDecode(jsonJString.toDartString(releaseOriginal: true));

          case 'getPageList':
            final sourceId = (args['sourceId'] as String).toJString()..releasedBy(arena);
            final epMap = args['episode'] as Map;
            final url = (epMap['url'] as String? ?? '').toJString()..releasedBy(arena);
            final name = (epMap['name'] as String? ?? '').toJString()..releasedBy(arena);

            final jsonJString = await AniyomiSourceMethods.INSTANCE.fetchPageList(
              sourceId,
              url,
              name,
            );
            return jsonDecode(jsonJString.toDartString(releaseOriginal: true));

          case 'unloadExtension':
            final sourceId = (args['sourceId'] as String).toJString()..releasedBy(arena);
            AniyomiSourceMethods.INSTANCE.unloadExtension(sourceId);
            return null;

          case 'aniyomiGetPreferences':
            final sourceId = (args['sourceId'] as String).toJString()..releasedBy(arena);
            final isAnime = args['isAnime'] as bool;

            final jsonJString = AniyomiSourceMethods.INSTANCE.getPreferences(
              sourceId,
              isAnime.toJBoolean()..releasedBy(arena),
            );
            return jsonJString.toDartString(releaseOriginal: true);

          case 'aniyomiSavePreference':
            final sourceId = (args['sourceId'] as String).toJString()..releasedBy(arena);
            final key = (args['key'] as String).toJString()..releasedBy(arena);
            final value = args['value'];
            final isAnime = args['isAnime'] as bool;

            JObject jValueObj;
            if (value is bool) {
              jValueObj = value.toJBoolean()..releasedBy(arena);
            } else if (value is String) {
              jValueObj = value.toJString()..releasedBy(arena);
            } else if (value is List) {
              final list = JList.array(JString.type)..releasedBy(arena);
              for (final item in value) {
                list.add(item.toString().toJString()..releasedBy(arena));
              }
              jValueObj = list;
            } else {
              jValueObj = (value?.toString() ?? '').toJString()..releasedBy(arena);
            }

            final result = AniyomiSourceMethods.INSTANCE.savePreference(
              sourceId,
              key,
              jValueObj,
              isAnime.toJBoolean()..releasedBy(arena),
            );

            return result.toDartString(releaseOriginal: true) == 'success';

          case 'csLoadExtensions':
            final folderPath = args['folderPath'] as String;
            final jsonJString = await CloudStreamExtensionLoader.INSTANCE.loadExtensions(
              folderPath.toJString()..releasedBy(arena),
            );
            return jsonDecode(jsonJString.toDartString(releaseOriginal: true));

          case 'csSearch':
            final sourceId = (args['sourceId'] as String).toJString()..releasedBy(arena);
            final query = (args['query'] as String).toJString()..releasedBy(arena);
            final page = args['page'] as int;

            final jsonJString = await CloudStreamExtensionLoader.INSTANCE.search(
              sourceId,
              query,
              page,
            );
            return jsonDecode(jsonJString.toDartString(releaseOriginal: true));

          case 'csGetDetail':
            final sourceId = (args['sourceId'] as String).toJString()..releasedBy(arena);
            final url = (args['url'] as String).toJString()..releasedBy(arena);

            final jsonJString = await CloudStreamExtensionLoader.INSTANCE.fetchDetails(
              sourceId,
              url,
            );
            return jsonDecode(jsonJString.toDartString(releaseOriginal: true));

          case 'csGetVideoList':
            final sourceId = (args['sourceId'] as String).toJString()..releasedBy(arena);
            final url = (args['url'] as String).toJString()..releasedBy(arena);

            final jsonJString = await CloudStreamExtensionLoader.INSTANCE.fetchVideoList(
              sourceId,
              url,
            );
            return jsonDecode(jsonJString.toDartString(releaseOriginal: true));

          default:
            throw UnimplementedError(
                'Method $method is not implemented in JniBridge.');
        }
      });
    });
  }

  void dispose() {
    _initialized = false;
  }

  Future<bool> cancelRequest(String id) async {
    print('JNI Bridge: cancelRequest called for $id (Not yet supported in JNI mode)');
    return false;
  }
}
