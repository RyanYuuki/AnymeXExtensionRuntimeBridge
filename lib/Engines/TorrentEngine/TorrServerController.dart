import 'dart:io';
import 'dart:typed_data';

import 'Models/TorrentInfo.dart';
import 'Models/TorrServerSettings.dart';

/// Abstract unified interface for controlling TorrServer across all platforms.
abstract class TorrServerController {
  /// Starts TorrServer (subprocess on desktop/Android, in-process FFI on iOS).
  ///
  /// Automatically allocates a free local TCP port unless [port] is explicitly provided.
  /// Throws [TorrServerStartException] on any failure (binary not found, port unavailable,
  /// process crash, FFI error, or timeout).
  Future<void> start({
    int? port,
    TorrServerSettings? settings,
    Directory? dataDir,
    List<String>? extraArgs,
    String? customBinaryPath,
  });

  /// Stops TorrServer cleanly.
  ///
  /// Waits for complete shutdown (with bounded timeout, force-killing if necessary
  /// on subprocess platforms) before returning.
  Future<void> stop();

  /// Returns true only if the server is confirmed running via verified health check.
  bool get isRunning;

  /// Base URL of the running TorrServer instance (e.g. `http://127.0.0.1:8090`),
  /// or null if the server is not running.
  Uri? get baseUrl;

  /// Allocated or assigned TCP port of the running instance, or null if stopped.
  int? get port;

  /// Adds a torrent to TorrServer via magnet link or raw `.torrent` file bytes.
  ///
  /// Throws [TorrServerInvalidTorrentException] if neither [magnet] nor [torrentFile] is provided.
  Future<TorrentInfo> addTorrent({
    String? magnet,
    Uint8List? torrentFile,
    String? title,
    String? category,
    String? poster,
    String? data,
    bool saveToDb = false,
  });

  /// Lists all active and stored torrents on the server.
  Future<List<TorrentInfo>> listTorrents();

  /// Gets status and live metrics for a specific torrent by its infohash.
  Future<TorrentInfo> getTorrent(String hash);

  /// Removes a torrent and its associated cache from TorrServer.
  Future<void> removeTorrent(String hash);

  /// Drops a torrent from active memory (freeing RAM).
  Future<void> dropTorrent(String hash);

  /// Updates metadata properties for a torrent.
  Future<void> setTorrent(
    String hash, {
    String? title,
    String? poster,
    String? category,
    String? data,
  });

  /// Constructs the playable HTTP streaming URL for a given torrent and file index.
  Uri streamUrl(String hash, {int fileIndex = 0});

  /// Retrieves current server configuration settings (`BTSets`).
  Future<TorrServerSettings> getSettings();

  /// Updates server configuration settings (`BTSets`).
  Future<void> setSettings(TorrServerSettings settings);

  /// Resets server configuration settings to defaults.
  Future<void> setDefaultSettings();

  /// Sends a health-check echo request and returns the TorrServer version.
  Future<String> echo();
}
