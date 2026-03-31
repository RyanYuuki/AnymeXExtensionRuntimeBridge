import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'package:jni/jni.dart';
import '../Runtime/RuntimePaths.dart';
import '../Runtime/RuntimeController.dart';

class JniBridge {
  static final JniBridge _instance = JniBridge._internal();
  factory JniBridge() => _instance;
  JniBridge._internal();

  bool _initialized = false;
  JClass? _bridgeClass;
  String? _bridgeJarPath;

  Future<void> initialize(String bridgeJarPath) async {
    if (_initialized) return;
    _bridgeJarPath = bridgeJarPath;

    final paths = RuntimePaths();
    final jvmPath = await paths.jvmLibPath;
    
    if (jvmPath == null) {
      throw StateError('JVM library not found. Please ensure JRE is installed via RuntimeDownloader.');
    }

    try {
      ffi.DynamicLibrary.open(jvmPath);
    } catch (e) {
      print('Warning: Failed to preload JVM library at $jvmPath: $e');
    }

    Jni.spawnIfNotExists(
      classPath: [bridgeJarPath],
    );

    _bridgeClass = JClass.forName('com/anymex/desktop/DesktopExtensionLoader');

    _initialized = true;
    print('JNI Bridge initialized with $bridgeJarPath using JVM: $jvmPath');
  }

  JClass get _bridge {
    if (!_initialized || _bridgeClass == null) {
      throw StateError('JniBridge is not initialized. Call initialize() first.');
    }
    return _bridgeClass!;
  }
  Future<dynamic> invokeMethod(String method, Map<String, dynamic> args) async {
    if (!_initialized || _bridgeJarPath == null) {
      throw StateError('JniBridge is not initialized. Call initialize() first.');
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

      Jni.spawnIfNotExists(
        classPath: [bridgeJarPath],
      );

      final bridge = JClass.forName('com/anymex/desktop/DesktopExtensionLoader');

      try {
        switch (method) {
          case 'loadExtensions':
            final folderPath = args['folderPath'] as String;
            final jFolderPath = folderPath.toJString();
            final jsonString = bridge
                .staticMethodId('loadExtensions', '(Ljava/lang/String;)Ljava/lang/String;')
                .call(bridge, JString.type, [jFolderPath])
                .toDartString(releaseOriginal: true);
            jFolderPath.release();
            return jsonDecode(jsonString);

          case 'getPopular':
          case 'getLatestUpdates':
            final isPopular = method == 'getPopular';
            final jClassName = (args['sourceId'] as String).toJString();
            final page = args['page'] as int;
            final isAnime = args['isAnime'] as bool;

            final methodName = isPopular ? 'fetchPopular' : 'fetchLatestUpdates';
            final jsonString = bridge
                .staticMethodId(methodName, '(Ljava/lang/String;ILjava/lang/Object;)Ljava/lang/String;')
                .call(bridge, JString.type, [jClassName, JValueInt(page), isAnime.toJBoolean()])
                .toDartString(releaseOriginal: true);

            jClassName.release();
            return jsonDecode(jsonString);

          case 'search':
            final jClassName = (args['sourceId'] as String).toJString();
            final jQuery = (args['query'] as String).toJString();
            final page = args['page'] as int;
            final isAnime = args['isAnime'] as bool;

            final jsonString = bridge
                .staticMethodId('search', '(Ljava/lang/String;Ljava/lang/String;ILjava/lang/Object;)Ljava/lang/String;')
                .call(bridge, JString.type, [jClassName, jQuery, JValueInt(page), isAnime.toJBoolean()])
                .toDartString(releaseOriginal: true);

            jClassName.release();
            jQuery.release();
            return jsonDecode(jsonString);

          case 'getDetail':
            final jClassName = (args['sourceId'] as String).toJString();
            final mediaMap = args['media'] as Map;
            final jUrl = (mediaMap['url'] as String?)?.toJString();
            final jTitle = (mediaMap['title'] as String?)?.toJString();
            final jCover = (mediaMap['thumbnail_url'] as String?)?.toJString();
            final isAnime = args['isAnime'] as bool;

            final jsonString = bridge
                .staticMethodId('fetchDetails',
                    '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/Object;)Ljava/lang/String;')
                .call(bridge, JString.type, [
              jClassName,
              jUrl ?? ''.toJString(),
              jTitle ?? ''.toJString(),
              jCover ?? ''.toJString(),
              isAnime.toJBoolean()
            ]).toDartString(releaseOriginal: true);

            jClassName.release();
            jUrl?.release();
            jTitle?.release();
            jCover?.release();

            return jsonDecode(jsonString);

          case 'getVideoList':
            final jClassName = (args['sourceId'] as String).toJString();
            final epMap = args['episode'] as Map;
            final jUrl = (epMap['url'] as String?)?.toJString();
            final jName = (epMap['name'] as String?)?.toJString();

            final jsonString = bridge
                .staticMethodId('fetchVideoList', '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;')
                .call(bridge, JString.type, [jClassName, jUrl ?? ''.toJString(), jName ?? ''.toJString()])
                .toDartString(releaseOriginal: true);

            jClassName.release();
            jUrl?.release();
            jName?.release();

            return jsonDecode(jsonString);

          case 'getPageList':
            final jClassName = (args['sourceId'] as String).toJString();
            final epMap = args['episode'] as Map;
            final jUrl = (epMap['url'] as String?)?.toJString();
            final jName = (epMap['name'] as String?)?.toJString();

            final jsonString = bridge
                .staticMethodId('fetchPageList', '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;')
                .call(bridge, JString.type, [jClassName, jUrl ?? ''.toJString(), jName ?? ''.toJString()])
                .toDartString(releaseOriginal: true);

            jClassName.release();
            jUrl?.release();
            jName?.release();

            return jsonDecode(jsonString);

          case 'unloadExtension':
            final jClassName = (args['sourceId'] as String).toJString();
            bridge
                .staticMethodId('unloadExtension', '(Ljava/lang/String;)V')
                .call(bridge, jvoid.type, [jClassName]);
            jClassName.release();
            return null;

          default:
            throw UnimplementedError('Method $method is not implemented in JniBridge.');
        }
      } finally {
        bridge.release();
      }
    });
  }

  void dispose() {
    _bridgeClass?.release();
    _bridgeClass = null;
    _initialized = false;
  }
}
