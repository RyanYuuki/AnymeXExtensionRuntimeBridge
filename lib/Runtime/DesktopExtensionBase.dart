import 'dart:async';
import 'dart:io';
import 'package:get/get.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../Extensions/Extensions.dart';
import '../Logger.dart';
import 'RuntimePaths.dart';
import 'RuntimeController.dart';
import 'Bridge/BridgeDispatcher.dart';

abstract class DesktopExtensionBase extends Extension {
  @override
  Future<void> initialize() async {
    if (!Get.isRegistered<RuntimeController>()) {
      Get.put(RuntimeController());
    }

    final paths = RuntimePaths();
    final controller = RuntimeController.it;

    if (controller.isReady.value) {
      final bridgeJarPath = await paths.bridgePath;
      await BridgeDispatcher().initialize(bridgeJarPath);
    } else {
      Logger.log("AnymeX Bridge initialization deferred for $id: Runtime not ready.");
    }

    await super.initialize();
  }

  Future<String> getToolsPath() async {
    final dir = await RuntimePaths().toolsDir;
    return dir.path;
  }

  Future<String> getExtensionsPath(String subFolder) async {
    final dir = await RuntimePaths().extensionsDir;
    final targetDir = Directory(p.join(dir.path, subFolder));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    return targetDir.path;
  }

  Future<void> extractZip(String archivePath, String targetDir) async {
    final bytes = await File(archivePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    
    final directory = Directory(targetDir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

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
