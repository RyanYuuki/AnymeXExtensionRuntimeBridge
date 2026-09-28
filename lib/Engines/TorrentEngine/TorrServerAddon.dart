import 'dart:ffi';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../ExtensionBridge.dart';
import '../../Extensions/Addon.dart';
import '../../Logger.dart';
import '../../Settings/KvStore.dart';
import 'Models/TorrentInfo.dart';
import 'TorrServerController.dart';
import 'TorrServerControllerIos.dart';
import 'TorrServerControllerSubprocess.dart';

class TorrServerAddon extends Addon {
  final http.Client _client = AnymeXExtensionBridge.context.http ?? http.Client();

  TorrServerController? _controller;
  String? _activeHash;

  TorrServerAddon();

  static const _streamableExtensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.webm',
    '.m4v',
    '.flv',
    '.wmv',
    '.ts',
    '.mp3',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.wav',
  };

  Future<TorrServerController> ensureStarted() async {
    final controller = _controller ??= Platform.isIOS
        ? TorrServerControllerIos()
        : TorrServerControllerSubprocess();

    if (!controller.isRunning) {
      await controller.start(customBinaryPath: await binaryPath);
    }

    return controller;
  }

  TorrServerController? get controller => _controller;
  bool get isRunning => _controller?.isRunning ?? false;

  Future<void> stop() async {
    await _controller?.stop();
    _controller = null;
    _activeHash = null;
  }

  Future<String>? _startStreamFuture;

  Future<String> startStream({
    required String url,
    String? title,
    String? category,
    String? poster,
    String? episode,
    int? preferredFileIndex,
  }) {
    final inFlight = _startStreamFuture;
    if (inFlight != null) return inFlight;

    final future = _startStreamImpl(
      url: url,
      title: title,
      category: category,
      poster: poster,
      episode: episode,
      preferredFileIndex: preferredFileIndex,
    );
    return _startStreamFuture = future.whenComplete(
      () => _startStreamFuture = null,
    );
  }

  Future<String> _startStreamImpl({
    required String url,
    String? title,
    String? category,
    String? poster,
    String? episode,
    int? preferredFileIndex,
  }) async {
    final controller = await ensureStarted();
    await stopStream();

    late final TorrentInfo added;
    if (url.startsWith("magnet:")) {
      added = await controller.addTorrent(
        magnet: url,
        title: title,
        category: category,
        poster: poster,
      );
    } else if (url.startsWith("http://") || url.startsWith("https://")) {
      final torrentFile = await _downloadTorrentFile(url);
      try {
        added = await controller.addTorrent(
          torrentFile: await torrentFile.readAsBytes(),
          title: title,
          category: category,
          poster: poster,
        );
      } finally {
        if (await torrentFile.exists()) {
          await torrentFile.delete();
        }
      }
    } else {
      added = await controller.addTorrent(
        torrentFile: await File(url).readAsBytes(),
        title: title,
        category: category,
        poster: poster,
      );
    }

    _activeHash = added.hash;

    final info = await _waitForMetadata(controller, added.hash);
    final selected = _selectStreamableFile(
      info,
      episode: episode,
      preferredFileIndex: preferredFileIndex,
    );

    if (selected == null) {
      throw Exception("No streamable file found in torrent.");
    }

    return controller.streamUrl(info.hash, fileIndex: selected.id).toString();
  }

  Future<void> stopStream() async {
    final hash = _activeHash;
    _activeHash = null;
    if (hash == null) return;

    try {
      await _controller?.removeTorrent(hash);
    } catch (_) {}
  }

  Future<TorrentInfo> _waitForMetadata(
    TorrServerController controller,
    String hash, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final info = await controller.getTorrent(hash);
      if (info.fileStats.isNotEmpty) return info;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    throw Exception(
      "Timed out waiting for torrent metadata (${timeout.inSeconds}s)",
    );
  }

  TorrentFileStat? _selectStreamableFile(
    TorrentInfo info, {
    String? episode,
    int? preferredFileIndex,
  }) {
    final streamable = info.fileStats.where((file) {
      return _streamableExtensions.contains(
        p.extension(file.path).toLowerCase(),
      );
    }).toList();

    if (streamable.isEmpty) return null;

    if (preferredFileIndex != null) {
      for (final file in streamable) {
        if (file.id == preferredFileIndex) return file;
      }
    }

    if (episode != null) {
      final matched = _findFileIndexForEpisode(streamable, episode);
      if (matched != null) return matched;
    }

    TorrentFileStat? selected;
    for (final file in streamable) {
      if (selected == null || file.length > selected.length) {
        selected = file;
      }
    }

    return selected;
  }

  TorrentFileStat? _findFileIndexForEpisode(
    List<TorrentFileStat> files,
    String episode,
  ) {
    final intEp = int.tryParse(episode);
    if (intEp == null) return null;

    final normalizedEpisode = intEp.toString();
    final paddedEpisode = intEp.toString().padLeft(2, '0');

    final epPattern1 = RegExp(
      r'\b(?:e|ep|episode|ep\.)\s*0*' + normalizedEpisode + r'\b',
      caseSensitive: false,
    );

    for (final file in files) {
      final name = p.basename(file.path).toLowerCase();
      if (epPattern1.hasMatch(name)) {
        return file;
      }
    }

    for (final file in files) {
      final name = p.basename(file.path).toLowerCase();
      final matches = RegExp(r'\b\d+\b').allMatches(name);
      for (final match in matches) {
        final numStr = match.group(0);
        if (numStr == null) continue;
        final numVal = int.tryParse(numStr);
        if (numVal == intEp) {
          if (intEp == 720 ||
              intEp == 1080 ||
              intEp == 2160 ||
              intEp == 480 ||
              (intEp >= 1990 && intEp <= 2030)) {
            continue;
          }
          return file;
        }
      }
    }

    for (final file in files) {
      final name = p.basename(file.path).toLowerCase();
      if (name.contains('e$paddedEpisode') ||
          name.contains('ep$paddedEpisode') ||
          name.contains('episode $paddedEpisode') ||
          name.contains('e$normalizedEpisode') ||
          name.contains('ep$normalizedEpisode') ||
          name.contains('episode $normalizedEpisode')) {
        return file;
      }
    }

    return null;
  }

  Future<File> _downloadTorrentFile(String url) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(dir.path, "${DateTime.now().millisecondsSinceEpoch}.torrent"),
    );

    final response = await _client.get(Uri.parse(url));
    await file.writeAsBytes(response.bodyBytes);

    return file;
  }

  @override
  String get id => "torrserver";

  @override
  String get name => "TorrServer";

  @override
  IconData get icon => Icons.extension;

  static const _owner = "ayman708-UX";
  static const _repo = "torrserver_flutter";
  static const _version = "v0.0.6";

  String get version => _version;

  String get _versionKey => "${id}_version";
  String get _updateKey => "${id}_update";

  Future<Directory> get _directory async {
    final dir = await AnymeXExtensionBridge.context.getDirectory(
      subPath: "bridge/torrserver",
      useSystemPath: true,
      useCustomPath: false,
    );

    if (dir == null) {
      throw Exception("Failed to get TorrServer directory");
    }

    await dir.create(recursive: true);

    return dir;
  }

  String get _binaryName =>
      Platform.isWindows ? "torrserver.exe" : "torrserver";

  Future<File> get _binaryFile async =>
      File(p.join((await _directory).path, _binaryName));

  Future<String?> get binaryPath async {
    final file = await _binaryFile;
    return await file.exists() ? file.path : null;
  }

  @override
  Future<bool> isInstalled() async {
    if (Platform.isIOS) return true;
    return (await _binaryFile).exists();
  }

  String get _archiveName {
    if (Platform.isWindows) {
      return "torrserver-windows-amd64.zip";
    }
    if (Platform.isMacOS) {
      final arch = _isArm ? "arm64" : "amd64";
      return "torrserver-darwin-$arch.tar.gz";
    }
    if (Platform.isLinux) {
      final arch = _isArm ? "arm64" : "amd64";
      return "torrserver-linux-$arch.tar.gz";
    }
    if (Platform.isAndroid) {
      return "torrserver-android-$_androidAbi.zip";
    }
    throw UnsupportedError(
      "TorrServerAddon only downloads for Windows/macOS/Linux/Android; "
      "iOS embeds its xcframework instead.",
    );
  }

  String get _entryName {
    if (Platform.isWindows) return "torrserver-windows-amd64.exe";
    if (Platform.isMacOS) {
      return "torrserver-darwin-${_isArm ? "arm64" : "amd64"}";
    }
    if (Platform.isAndroid) return "torrserver-android-$_androidAbi";
    return "torrserver-linux-${_isArm ? "arm64" : "amd64"}";
  }

  bool get _isArm =>
      Platform.version.toLowerCase().contains("arm") ||
      Platform.version.toLowerCase().contains("aarch64");

  String get _androidAbi {
    switch (Abi.current()) {
      case Abi.androidArm64:
        return "arm64";
      case Abi.androidArm:
        return "arm7";
      case Abi.androidX64:
        return "amd64";
      case Abi.androidIA32:
        return "386";
      default:
        throw UnsupportedError("Unsupported Android ABI: ${Abi.current()}");
    }
  }

  @override
  Future<void> install() async {
    if (downloading.value) return;

    downloading.value = true;
    progress.value = 0;

    try {
      await _download();

      installed.value = true;
      hasUpdate.value = false;
      setVal(_versionKey, _version);

      Logger.log("Installed TorrServer", show: true);
    } finally {
      downloading.value = false;
    }
  }

  @override
  Future<void> uninstall() async {
    await _controller?.stop();
    _controller = null;
    _activeHash = null;

    final dir = await _directory;

    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    installed.value = false;
    hasUpdate.value = false;

    setVal(_versionKey, "");
    setVal(_updateKey, false);
  }

  @override
  Future<bool> checkForUpdate() async {
    if (!await isInstalled()) return false;
    if (Platform.isIOS) return false;

    final local = getVal<String>(_versionKey, defaultValue: "") ?? "";
    final update = _version != local;

    setVal(_updateKey, update);
    hasUpdate.value = update;
    return update;
  }

  @override
  Future<void> update() async {
    if (!await checkForUpdate()) return;
    await uninstall();
    await install();
  }

  Future<void> _download() async {
    final url =
        "https://github.com/$_owner/$_repo/releases/download/$_version/$_archiveName";

    final request = http.Request("GET", Uri.parse(url));
    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw Exception("Failed to download TorrServer (${response.statusCode})");
    }

    final dir = await _directory;
    final archiveFile = File(p.join(dir.path, _archiveName));

    final sink = archiveFile.openWrite();
    int received = 0;
    final total = response.contentLength ?? 0;

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        progress.value = received / total;
      }
    }

    await sink.flush();
    await sink.close();

    final bytes = await archiveFile.readAsBytes();
    final archive = _archiveName.endsWith(".zip")
        ? ZipDecoder().decodeBytes(bytes)
        : TarDecoder().decodeBytes(const GZipDecoder().decodeBytes(bytes));

    final entry = archive.files.firstWhere(
      (f) => f.isFile && p.basename(f.name) == _entryName,
      orElse: () => throw Exception("$_entryName not found in $_archiveName"),
    );

    final binary = await _binaryFile;
    await binary.writeAsBytes(entry.content as List<int>);
    await archiveFile.delete();

    if (!Platform.isWindows) {
      await Process.run("chmod", ["755", binary.path]);
    }

    progress.value = 1;
  }
}
