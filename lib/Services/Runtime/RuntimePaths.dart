import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../anymex_extension_runtime_bridge.dart';

class RuntimePaths {
  static final RuntimePaths _instance = RuntimePaths._internal();
  factory RuntimePaths() => _instance;
  RuntimePaths._internal();

  Future<Directory> get runtimeDir async {
    final isDocsBased = Platform.isWindows || Platform.isAndroid;
    final baseDir = isDocsBased
        ? await getApplicationDocumentsDirectory()
        : await getApplicationSupportDirectory();

    final dir = Directory(
        p.join(baseDir.path, p.basename(AnymeXExtensionBridge.projectName)));

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> get toolsDir async {
    final root = await runtimeDir;
    final folderName = Platform.isWindows ? 'Tools' : 'Runtime';
    final dir = Directory(p.join(root.path, folderName));

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> get extensionsDir async {
    final root = await runtimeDir;
    final dir = Directory(p.join(root.path, 'Extensions'));

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> get bridgePath async {
    final dir = await toolsDir;
    final fileName = Platform.isAndroid
        ? 'anymex_runtime_host.apk'
        : 'anymex_desktop_runtime.jar';
    return p.join(dir.path, fileName);
  }

  Future<Directory> get jreDir async {
    final dir = await toolsDir;
    return Directory(p.join(dir.path, 'jre'));
  }

  Future<String?> get jvmLibPath async {
    if (Platform.isAndroid) return null;

    final jreRoot = await jreDir;
    if (!await jreRoot.exists()) return null;

    String relativePath;
    if (Platform.isWindows) {
      relativePath = p.join('bin', 'server', 'jvm.dll');
    } else if (Platform.isMacOS) {
      final macBundlePath =
          p.join('Contents', 'Home', 'lib', 'server', 'libjvm.dylib');
      final macPath = p.join('lib', 'server', 'libjvm.dylib');

      if (await File(p.join(jreRoot.path, macBundlePath)).exists()) {
        return p.join(jreRoot.path, macBundlePath);
      }
      relativePath = macPath;
    } else {
      relativePath = p.join('lib', 'server', 'libjvm.so');
    }

    final fullPath = p.join(jreRoot.path, relativePath);
    if (await File(fullPath).exists()) {
      return fullPath;
    }

    return _findFileRecursive(jreRoot, Platform.isWindows ? 'jvm.dll' : (Platform.isMacOS ? 'libjvm.dylib' : 'libjvm.so'));
  }

  Future<String?> get javaExecutablePath async {
    if (Platform.isAndroid) return null;

    final jreRoot = await jreDir;
    if (!await jreRoot.exists()) return null;

    final exeName = Platform.isWindows ? 'java.exe' : 'java';
    final path = p.join(jreRoot.path, 'bin', exeName);

    if (await File(path).exists()) {
      return path;
    }

    if (Platform.isMacOS) {
      final macPath = p.join(jreRoot.path, 'Contents', 'Home', 'bin', 'java');
      if (await File(macPath).exists()) {
        return macPath;
      }
      return _findFileRecursive(jreRoot, 'java');
    }

    return null;
  }

  Future<String?> _findFileRecursive(Directory dir, String fileName) async {
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && p.basename(entity.path) == fileName) {
          return entity.path;
        }
      }
    } catch (_) {}
    return null;
  }

}
