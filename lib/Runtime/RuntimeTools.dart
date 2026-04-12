import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import 'RuntimePaths.dart';
import '../Logger.dart';

class RuntimeTools {
  static final RuntimeTools _instance = RuntimeTools._internal();
  factory RuntimeTools() => _instance;
  RuntimeTools._internal();

  final _paths = RuntimePaths();
  final _client = http.Client();

  Future<String> ensureDex2Jar() async {
    final toolsDir = await _paths.toolsDir;
    final dex2jarExt = Platform.isWindows ? 'bat' : 'sh';
    final dex2jarPath = p.join(toolsDir.path, 'dex-tools-v2.4', 'd2j-dex2jar.$dex2jarExt');

    if (!File(dex2jarPath).existsSync()) {
      Logger.log("Dex2Jar not found, downloading...");
      final zipUri = "https://github.com/pxb1988/dex2jar/releases/download/v2.4/dex-tools-v2.4.zip";
      final zipPath = p.join(toolsDir.path, 'dex2jar.zip');

      final res = await _client.get(Uri.parse(zipUri));
      if (res.statusCode != 200 && res.statusCode != 302) {
        throw Exception('Failed to download Dex2Jar: HTTP ${res.statusCode}');
      }
      File(zipPath).writeAsBytesSync(res.bodyBytes);

      try {
        await _extractZip(zipPath, toolsDir.path);
        if (File(zipPath).existsSync()) File(zipPath).deleteSync();
        Logger.log("Dex2Jar installed successfully.");
      } catch (e) {
        throw Exception('Failed to install Dex2Jar: $e');
      }
    }

    if (Platform.isLinux || Platform.isMacOS) {
      await Process.run('chmod', ['+x', dex2jarPath]);
      final dexToolsBinDir = Directory(p.dirname(dex2jarPath));
      if (await dexToolsBinDir.exists()) {
        await for (final file in dexToolsBinDir.list()) {
          if (file is File && file.path.endsWith('.sh')) {
            await Process.run('chmod', ['+x', file.path]);
          }
        }
      }
    }

    return dex2jarPath;
  }

  Future<void> runDex2Jar(String dexPath, String outJarPath) async {
    final dex2jarPath = await ensureDex2Jar();
    final javaPath = await _paths.javaExecutablePath;

    if (javaPath == null) {
      throw Exception("Java executable not found. Cannot run dex2jar.");
    }

    final javaBinDir = p.dirname(javaPath);
    final env = Map<String, String>.from(Platform.environment);
    final pathKey = env.keys.firstWhere((k) => k.toUpperCase() == 'PATH', orElse: () => 'PATH');
    final separator = Platform.isWindows ? ';' : ':';
    
    env[pathKey] = '$javaBinDir$separator${env[pathKey] ?? ''}';
    env['JAVA_HOME'] = p.dirname(javaBinDir);

    final process = await Process.run(
      dex2jarPath, 
      ['--force', dexPath, '-o', outJarPath],
      environment: env
    );

    if (process.exitCode != 0) {
      throw Exception('dex2jar compilation failed: ${process.stderr}\n${process.stdout}');
    }
  }

  Future<void> _extractZip(String archivePath, String targetDir) async {
    final bytes = await File(archivePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        File(p.join(targetDir, filename))
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      } else {
        Directory(p.join(targetDir, filename)).createSync(recursive: true);
      }
    }
  }
}
