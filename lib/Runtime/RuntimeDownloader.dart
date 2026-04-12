import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import '../AnymeXBridge.dart';
import 'RuntimePaths.dart';
import 'RuntimeController.dart';

class RuntimeDownloader {
  static final RuntimeDownloader _instance = RuntimeDownloader._internal();
  factory RuntimeDownloader() => _instance;
  RuntimeDownloader._internal();

  final _paths = RuntimePaths();
  final _client = http.Client();

  static const String androidApkUrl = 
      "https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge/releases/latest/download/anymex_runtime_host.apk";
  static const String desktopJarUrl = 
      "https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge/releases/latest/download/anymex_desktop_runtime.jar";

  static String get _jreUrl {
    if (Platform.isWindows) {
      return "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_x64_windows_hotspot_17.0.12_7.zip";
    } else if (Platform.isMacOS) {
      final arch = _getMacArch();
      if (arch == 'arm64') {
        return "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_aarch64_mac_hotspot_17.0.12_7.tar.gz";
      } else {
        return "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_x64_mac_hotspot_17.0.12_7.tar.gz";
      }
    } else {
      final arch = _getLinuxArch();
      if (arch == 'aarch64' || arch == 'arm64') {
        return "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_aarch64_linux_hotspot_17.0.12_7.tar.gz";
      } else {
        return "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12+7/OpenJDK17U-jre_x64_linux_hotspot_17.0.12_7.tar.gz";
      }
    }
  }

  static String _getMacArch() {
    try {
      final result = Process.runSync('uname', ['-m']);
      return result.stdout.toString().trim().toLowerCase();
    } catch (_) {
      return 'x64';
    }
  }

  static String _getLinuxArch() {
    try {
      final result = Process.runSync('uname', ['-m']);
      return result.stdout.toString().trim().toLowerCase();
    } catch (_) {
      return 'x64';
    }
  }

  Future<void> setupRuntime({String? customUrl, bool force = false, String? localApkPath}) async {
    final controller = RuntimeController.it;
    if (controller.isDownloading.value) return;

    controller.isDownloading.value = true;
    controller.updateStatus("Initializing setup...");
    controller.updateProgress(0.0, "");

    try {
      final bridgePath = await _paths.bridgePath;
      final bridgeFile = File(bridgePath);
      final jreDir = await _paths.jreDir;

      bool needsBridge =
          (localApkPath == null) && (force || !await bridgeFile.exists());
      bool needsJre = !Platform.isAndroid && !await jreDir.exists();


      int totalFiles = (needsBridge ? 1 : 0) + (needsJre ? 1 : 0);
      int currentFileIndex = 0;

      if (needsBridge) {
        currentFileIndex++;
        final downloadUrl = customUrl ?? (Platform.isAndroid ? androidApkUrl : desktopJarUrl);
        final label = Platform.isAndroid ? "Runtime APK" : "Bridge JAR";
        final stepPrefix = totalFiles > 1 ? "($currentFileIndex/$totalFiles) " : "";
        await _downloadFile(downloadUrl, bridgeFile.path, "$stepPrefix$label");
      }

      if (needsJre) {
        currentFileIndex++;
        final ext = Platform.isWindows ? ".zip" : ".tar.gz";
        final jreArchive = File(p.join((await _paths.runtimeDir).path, "jre_archive$ext"));
        
        final stepPrefix = totalFiles > 1 ? "($currentFileIndex/$totalFiles) " : "";
        await _downloadFile(_jreUrl, jreArchive.path, "$stepPrefix Runtime");
        
        controller.updateStatus("Extracting Java Runtime...");
        await _extractArchive(jreArchive.path, jreDir.path);
        
        if (await jreArchive.exists()) await jreArchive.delete();

        if (Platform.isMacOS) {
          controller.updateStatus("Applying macOS permissions...");
          await Process.run('xattr', ['-cr', jreDir.path]);
          final jreBinDir = Directory(p.join(jreDir.path, 'Contents', 'Home', 'bin'));
          if (await jreBinDir.exists()) {
            await Process.run('chmod', ['-R', '+x', jreBinDir.path]);
          } else {
            final altBinDir = Directory(p.join(jreDir.path, 'bin'));
            if (await altBinDir.exists()) {
              await Process.run('chmod', ['-R', '+x', altBinDir.path]);
            }
          }
        } else if (Platform.isLinux) {
          controller.updateStatus("Applying Linux permissions...");
          final binDir = Directory(p.join(jreDir.path, 'bin'));
          if (await binDir.exists()) {
            await Process.run('chmod', ['-R', '+x', binDir.path]);
          }
          final libDir = Directory(p.join(jreDir.path, 'lib'));
          if (await libDir.exists()) {
            await Process.run('chmod', ['-R', 'a+r', libDir.path]);
          }
        }
      }

      controller.updateStatus("Finalizing bridge...");
      bool isLoaded;
      
      if (Platform.isAndroid) {
        isLoaded = await AnymeXRuntimeBridge.loadAnymeXRuntimeHost(localApkPath ?? bridgeFile.path);
      } else {
        isLoaded = true; 
      }

      if (isLoaded) {
        controller.updateStatus("Ready.");
        controller.setReady(true);
      } else {
        throw Exception("Failed to load runtime bridge host.");
      }
    } catch (e) {
      if (e.toString().contains("404")) {
        controller.setError("Runtime not found! The release might not be published yet.");
      } else {
        controller.setError(e.toString());
      }
    } finally {
      controller.isDownloading.value = false;
    }
  }

  Future<void> _downloadFile(String url, String savePath, String label) async {
    final controller = RuntimeController.it;
    controller.updateStatus("Downloading $label...");

    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    
    if (response.statusCode != 200) {
      throw Exception("Failed to download $label: HTTP ${response.statusCode}");
    }

    final totalSize = response.contentLength ?? 0;
    var downloaded = 0;
    final file = File(savePath);
    final sink = file.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      downloaded += chunk.length;
      
      if (totalSize > 0) {
        final progress = (downloaded / totalSize).clamp(0.0, 1.0);
        final info = "${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB / ${(totalSize / 1024 / 1024).toStringAsFixed(1)} MB";
        controller.updateProgress(progress, info);
      } else {
        controller.updateProgress(0.0, "${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB downloaded");
      }
    }
    await sink.close();
  }

  Future<void> _extractArchive(String archivePath, String targetDir) async {
    final targetDirObj = Directory(targetDir);
    if (!await targetDirObj.exists()) await targetDirObj.create(recursive: true);

    try {
      if (archivePath.endsWith('.zip')) {
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
      } else if (archivePath.endsWith('.tar.gz')) {
        final bytes = await File(archivePath).readAsBytes();
        final gzipBytes = GZipDecoder().decodeBytes(bytes);
        final archive = TarDecoder().decodeBytes(gzipBytes);
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
      } else {
        throw Exception("Unsupported archive format: $archivePath");
      }
    } catch (e) {
      throw Exception("Extraction failed: $e");
    }
    await _flattenJreFolder(targetDir);
  }

  Future<void> _flattenJreFolder(String jrePath) async {
    final dir = Directory(jrePath);
    final entities = await dir.list().toList();
    if (entities.length == 1 && entities.first is Directory) {
      final innerDir = entities.first as Directory;
      for (final entity in await innerDir.list().toList()) {
        final newPath = p.join(jrePath, p.basename(entity.path));
        await entity.rename(newPath);
      }
      await innerDir.delete();
    }
  }
}
