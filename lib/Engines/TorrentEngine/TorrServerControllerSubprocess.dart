import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'Exceptions.dart';
import 'Models/TorrentInfo.dart';
import 'Models/TorrServerSettings.dart';
import 'PortFinder.dart';
import 'RestClient.dart';
import 'TorrServerController.dart';

/// Subprocess implementation of [TorrServerController] for Windows, Linux, macOS, and Android.
///
/// The binary for every platform this runs on is downloaded at app runtime by
/// [TorrServerAddon] — [customBinaryPath] is how that path gets here.
class TorrServerControllerSubprocess implements TorrServerController {
  Process? _process;
  int? _port;
  Uri? _baseUrl;
  TorrServerRestClient? _restClient;
  bool _isRunning = false;
  final List<String> _processLogs = [];
  AppLifecycleListener? _lifecycleListener;
  StreamSubscription<ProcessSignal>? _sigintSub;
  StreamSubscription<ProcessSignal>? _sigtermSub;
  Directory? _currentDataDir;

  @override
  bool get isRunning => _isRunning;

  @override
  Uri? get baseUrl => _baseUrl;

  @override
  int? get port => _port;

  /// Recent process stdout/stderr log output lines.
  List<String> get processLogs => List.unmodifiable(_processLogs);

  Future<void>? _startFuture;

  @override
  Future<void> start({
    int? port,
    TorrServerSettings? settings,
    Directory? dataDir,
    List<String>? extraArgs,
    String? customBinaryPath,
  }) {
    if (_isRunning) {
      return Future.error(
        const TorrServerStartException('TorrServer is already running'),
      );
    }

    // _isRunning isn't set until _waitForServerReady() returns below (up to
    // 12s later), so without this guard two concurrent start() calls both
    // pass the check above and both spawn a binary/allocate a port - the
    // loser's process and port are then silently orphaned. This runs
    // synchronously (start() is deliberately not `async`), so it takes
    // effect before another caller's invocation gets a turn.
    final inFlight = _startFuture;
    if (inFlight != null) return inFlight;

    final future = _startImpl(
      port: port,
      settings: settings,
      dataDir: dataDir,
      extraArgs: extraArgs,
      customBinaryPath: customBinaryPath,
    );
    return _startFuture = future.whenComplete(() => _startFuture = null);
  }

  Future<void> _startImpl({
    int? port,
    TorrServerSettings? settings,
    Directory? dataDir,
    List<String>? extraArgs,
    String? customBinaryPath,
  }) async {
    final binaryPath = await _locateBinary(customBinaryPath: customBinaryPath);

    final resolvedDataDir = dataDir ?? await _getDefaultDataDir();
    if (!await resolvedDataDir.exists()) {
      await resolvedDataDir.create(recursive: true);
    }
    _currentDataDir = resolvedDataDir;

    var selectedPort = port ?? await PortFinder.findFreePort();
    await _cleanupOrphans(resolvedDataDir, selectedPort);

    final args = <String>[
      '-p',
      selectedPort.toString(),
      '-d',
      resolvedDataDir.path,
    ];

    if (extraArgs != null) {
      args.addAll(extraArgs);
    }

    _processLogs.clear();

    try {
      final process = await Process.start(
        binaryPath,
        args,
        mode: ProcessStartMode.normal,
      );

      _process = process;
      _port = selectedPort;
      _baseUrl = Uri.parse('http://127.0.0.1:$selectedPort');
      _restClient = TorrServerRestClient(_baseUrl!);

      try {
        final pidFile = _getPidFile(resolvedDataDir);
        await pidFile.writeAsString(process.pid.toString());
      } catch (_) {}

      process.stdout.transform(utf8.decoder).listen(_logProcessOutput);
      process.stderr.transform(utf8.decoder).listen(_logProcessOutput);

      unawaited(
        process.exitCode.then((code) {
          _isRunning = false;
          _process = null;
        }),
      );

      await _waitForServerReady(const Duration(seconds: 12));
      _isRunning = true;

      _setupLifecycleHooks();

      if (settings != null) {
        try {
          await _restClient!.setSettings(settings);
        } catch (_) {}
      }
    } catch (e) {
      await stop();
      if (e is TorrServerException) rethrow;
      throw TorrServerStartException(
        'Failed to start TorrServer subprocess: $e',
        e,
      );
    }
  }

  @override
  Future<void> stop() async {
    _disposeLifecycleHooks();
    final process = _process;
    final restClient = _restClient;
    final dataDir = _currentDataDir;

    _isRunning = false;
    _baseUrl = null;
    _process = null;
    _port = null;
    _restClient = null;

    if (restClient != null) {
      try {
        await restClient.shutdown(timeout: const Duration(seconds: 1));
      } catch (_) {}
      restClient.close();
    }

    if (process != null) {
      try {
        if (Platform.isWindows) {
          process.kill(ProcessSignal.sigkill);
        } else {
          process.kill(ProcessSignal.sigterm);
        }

        await process.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (_) {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }

    if (dataDir != null) {
      try {
        final pidFile = _getPidFile(dataDir);
        if (await pidFile.exists()) {
          await pidFile.delete();
        }
      } catch (_) {}
    }
  }

  void _setupLifecycleHooks() {
    try {
      _lifecycleListener ??= AppLifecycleListener(
        onDetach: () {
          unawaited(stop());
        },
        onExitRequested: () async {
          await stop();
          return AppExitResponse.exit;
        },
        onHide: () {
          // On mobile / desktop minimize, keep running.
        },
      );
    } catch (_) {}

    if (!Platform.isWindows && !Platform.isAndroid) {
      try {
        _sigintSub ??= ProcessSignal.sigint.watch().listen((_) {
          unawaited(stop());
        });
      } catch (_) {}
      try {
        _sigtermSub ??= ProcessSignal.sigterm.watch().listen((_) {
          unawaited(stop());
        });
      } catch (_) {}
    }
  }

  void _disposeLifecycleHooks() {
    try {
      _lifecycleListener?.dispose();
    } catch (_) {}
    _lifecycleListener = null;
    try {
      _sigintSub?.cancel();
    } catch (_) {}
    _sigintSub = null;
    try {
      _sigtermSub?.cancel();
    } catch (_) {}
    _sigtermSub = null;
  }

  File _getPidFile(Directory dataDir) =>
      File(p.join(dataDir.path, 'torrserver.pid'));

  Future<void> _cleanupOrphans(Directory dataDir, int targetPort) async {
    try {
      final pidFile = _getPidFile(dataDir);
      if (await pidFile.exists()) {
        final pidStr = (await pidFile.readAsString()).trim();
        final pid = int.tryParse(pidStr);
        if (pid != null && pid > 0) {
          try {
            Process.killPid(pid, ProcessSignal.sigterm);
            await Future<void>.delayed(const Duration(milliseconds: 150));
            Process.killPid(pid, ProcessSignal.sigkill);
          } catch (_) {}
        }
        await pidFile.delete().catchError((_) => pidFile);
      }
    } catch (_) {}

    final portsToCheck = {targetPort, 8090};
    for (final port in portsToCheck) {
      try {
        final probeClient = TorrServerRestClient(
          Uri.parse('http://127.0.0.1:$port'),
        );
        final echo = await probeClient.echo(
          timeout: const Duration(milliseconds: 300),
        );
        if (echo.isNotEmpty) {
          _logProcessOutput(
            'Shutting down lingering TorrServer on port $port ($echo)...',
          );
          await probeClient.shutdown(timeout: const Duration(seconds: 1));
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      } catch (_) {
        // Port is clear.
      }
    }
  }

  @override
  Future<TorrentInfo> addTorrent({
    String? magnet,
    Uint8List? torrentFile,
    String? title,
    String? category,
    String? poster,
    String? data,
    bool saveToDb = false,
  }) async {
    _ensureRunning();
    if (magnet != null && magnet.isNotEmpty) {
      return _restClient!.addTorrent(
        link: magnet,
        title: title,
        category: category,
        poster: poster,
        data: data,
        saveToDb: saveToDb,
      );
    } else if (torrentFile != null && torrentFile.isNotEmpty) {
      return _restClient!.uploadTorrentFile(
        torrentBytes: torrentFile,
        title: title,
        category: category,
        poster: poster,
        data: data,
        saveToDb: saveToDb,
      );
    }
    throw const TorrServerInvalidTorrentException(
      'Either magnet URI or torrentFile bytes must be provided',
    );
  }

  @override
  Future<List<TorrentInfo>> listTorrents() {
    _ensureRunning();
    return _restClient!.listTorrents();
  }

  @override
  Future<TorrentInfo> getTorrent(String hash) {
    _ensureRunning();
    return _restClient!.getTorrent(hash);
  }

  @override
  Future<void> removeTorrent(String hash) {
    _ensureRunning();
    return _restClient!.removeTorrent(hash);
  }

  @override
  Future<void> dropTorrent(String hash) {
    _ensureRunning();
    return _restClient!.dropTorrent(hash);
  }

  @override
  Future<void> setTorrent(
    String hash, {
    String? title,
    String? poster,
    String? category,
    String? data,
  }) {
    _ensureRunning();
    return _restClient!.setTorrent(
      hash,
      title: title,
      poster: poster,
      category: category,
      data: data,
    );
  }

  @override
  Uri streamUrl(String hash, {int fileIndex = 0}) {
    _ensureRunning();
    return _restClient!.streamUrl(hash, fileIndex: fileIndex);
  }

  @override
  Future<TorrServerSettings> getSettings() {
    _ensureRunning();
    return _restClient!.getSettings();
  }

  @override
  Future<void> setSettings(TorrServerSettings settings) {
    _ensureRunning();
    return _restClient!.setSettings(settings);
  }

  @override
  Future<void> setDefaultSettings() {
    _ensureRunning();
    return _restClient!.setDefaultSettings();
  }

  @override
  Future<String> echo() {
    _ensureRunning();
    return _restClient!.echo();
  }

  void _ensureRunning() {
    if (!_isRunning || _restClient == null) {
      throw const TorrServerProcessException('TorrServer is not running');
    }
  }

  Future<void> _waitForServerReady(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_process == null) {
        final logsStr = _processLogs.join('\n');
        if (logsStr.contains('Error open bboltDB') ||
            logsStr.contains('timeout')) {
          throw TorrServerStartException(
            'TorrServer process exited during startup due to database lock contention (bboltDB timeout on config.db). '
            'Logs: $logsStr',
          );
        }
        throw TorrServerStartException(
          'TorrServer process exited prematurely during startup. Logs: $logsStr',
        );
      }
      try {
        await _restClient!.echo(timeout: const Duration(milliseconds: 500));
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    throw TorrServerStartException(
      'TorrServer failed to respond to healthcheck within ${timeout.inSeconds} seconds. '
      'Logs: ${_processLogs.join("\n")}',
    );
  }

  void _logProcessOutput(String text) {
    final lines = text.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        _processLogs.add(trimmed);
        if (_processLogs.length > 200) {
          _processLogs.removeAt(0);
        }
      }
    }
  }

  Future<Directory> _getDefaultDataDir() async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      return Directory('${appSupport.path}/torrserver_data');
    } catch (_) {
      return Directory('${Directory.current.path}/torrserver_data');
    }
  }

  Future<String> _locateBinary({String? customBinaryPath}) async {
    if (customBinaryPath != null && customBinaryPath.isNotEmpty) {
      if (await File(customBinaryPath).exists()) {
        return customBinaryPath;
      }
      throw TorrServerBinaryNotFoundException(
        'TorrServer binary not found at $customBinaryPath',
        customBinaryPath,
      );
    }
    throw const TorrServerBinaryNotFoundException(
      'No TorrServer binary path given — pass customBinaryPath '
      '(TorrServerAddon.binaryPath).',
    );
  }
}
