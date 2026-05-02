import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import 'RuntimeController.dart';
import 'RuntimePaths.dart';
import '../Logger.dart';

class RuntimeTools {
  static final RuntimeTools _instance = RuntimeTools._internal();
  factory RuntimeTools() => _instance;
  RuntimeTools._internal();

  final _paths = RuntimePaths();
  final _client = http.Client();

  Future<String> ensureDex2Jar() async {
    final controller = RuntimeController.it;
    final toolsDir = await _paths.toolsDir;
    final dex2jarPath = await _paths.dex2jarPath;

    if (!File(dex2jarPath).existsSync()) {
      Logger.log("Dex2Jar not found, downloading as fallback...");

      const zipUri = "https://github.com/pxb1988/dex2jar/releases/download/v2.4/dex-tools-v2.4.zip";
      final zipPath = p.join(toolsDir.path, 'dex2jar.zip');

      controller.updateStatus("Downloading Dex2Jar...");
      controller.updateProgress(0.0, "");

      final request = http.Request('GET', Uri.parse(zipUri));
      final response = await _client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Failed to download Dex2Jar: HTTP ${response.statusCode}');
      }

      final totalSize = response.contentLength ?? 0;
      var downloaded = 0;
      final sink = File(zipPath).openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (totalSize > 0) {
          final progress = (downloaded / totalSize).clamp(0.0, 1.0);
          final info =
              "${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB / ${(totalSize / 1024 / 1024).toStringAsFixed(1)} MB";
          controller.updateProgress(progress, info);
        } else {
          controller.updateProgress(
              0.0, "${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB downloaded");
        }
      }
      await sink.close();

      try {
        controller.updateStatus("Extracting Dex2Jar...");
        await _extractZip(zipPath, toolsDir.path);
        if (File(zipPath).existsSync()) File(zipPath).deleteSync();
        Logger.log("Dex2Jar installed successfully.");
      } catch (e) {
        throw Exception('Failed to install Dex2Jar: $e');
      }
    }

    if (Platform.isLinux || Platform.isMacOS) {
      controller.updateStatus("Applying Dex2Jar permissions...");
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
    final pathKey =
        env.keys.firstWhere((k) => k.toUpperCase() == 'PATH', orElse: () => 'PATH');
    final separator = Platform.isWindows ? ';' : ':';

    env[pathKey] = '$javaBinDir$separator${env[pathKey] ?? ''}';
    env['JAVA_HOME'] = p.dirname(javaBinDir);

    final process = await Process.run(
      dex2jarPath,
      ['--force', dexPath, '-o', outJarPath],
      environment: env,
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
