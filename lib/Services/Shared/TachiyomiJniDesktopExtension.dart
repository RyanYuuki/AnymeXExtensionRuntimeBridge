import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../Logger.dart';
import '../../Extensions/Extensions.dart';
import '../../Models/Source.dart';
import '../../Runtime/RuntimePaths.dart';
import 'PackagedSource.dart';
import 'TachiyomiRepo.dart';

mixin TachiyomiJniDesktopExtension on Extension {
  http.Client get repoClient;
  String get jniDataDir;

  Future<Directory> extensionsDir(ItemType type) async {
    final root = await RuntimePaths().extensionsDir;
    final dir = Directory(p.join(root.path, jniDataDir, type.toString()));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<void> installSource(Source source) async {
    final s = source as PackagedSource;
    final type = source.itemType!;

    final downloadUrl = s.apkUrl;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw Exception("APK URL missing");
    }

    final fileName =
        s.apkName ?? s.pkgName ?? p.basename(Uri.parse(downloadUrl).path);
    if (fileName.isEmpty) {
      throw Exception("Can't determine a file name for ${s.name}");
    }

    final dir = await extensionsDir(type);
    final file = File(p.join(dir.path, fileName));

    final oldApkPath = s.apkPath;

    await downloadPackageFile(
      repoClient,
      downloadUrl,
      file.path,
    );

    s.apkPath = file.path;

    if (oldApkPath != null && oldApkPath != file.path) {
      final oldFile = File(oldApkPath);
      if (await oldFile.exists()) {
        await oldFile.delete();
        Logger.log('Deleted old extension: ${oldFile.path}');
      }
    }

    final avail = getAvailableRx(type);
    avail.value = avail.value.where((e) => e.id != s.id).toList();
    if (type == ItemType.novel) {
      await fetchInstalledNovelExtensions();
    } else if (type == ItemType.manga) {
      await fetchInstalledMangaExtensions();
    } else {
      await fetchInstalledAnimeExtensions();
    }
    detectTachiyomiUpdates(this, getRawAvailableRx(type).value, type);
  }

  @override
  Future<void> updateSource(Source source) => installSource(source);

  @override
  Future<void> uninstallSource(Source source) async {
    final s = source as PackagedSource;
    final type = source.itemType!;

    final apkFileName = s.apkPath != null
        ? p.basename(s.apkPath!)
        : (s.apkName ?? '${s.pkgName ?? s.id}.jar');

    final baseDir = await extensionsDir(type);
    final file = File(p.join(baseDir.path, apkFileName));

    if (await file.exists()) {
      await file.delete();
      Logger.log('Deleted private extension: ${s.name}');
    }

    if (type == ItemType.novel) {
      await fetchInstalledNovelExtensions();
    } else if (type == ItemType.manga) {
      await fetchInstalledMangaExtensions();
    } else {
      await fetchInstalledAnimeExtensions();
    }
    detectTachiyomiUpdates(this, getRawAvailableRx(type).value, type);
  }
}
