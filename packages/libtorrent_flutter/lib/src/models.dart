// Models for libtorrent_flutter

/// Torrent download state.
enum TorrentState {
  error,
  unknown,
  checkingFiles,
  downloadingMetadata,
  downloading,
  finished,
  seeding,
  allocating,
  checkingResume,
}

/// Stream playback state.
enum StreamState {
  idle,
  buffering,
  ready,
  seeking,
  error,
}

StreamState streamStateFromInt(int v) {
  switch (v) {
    case 0: return StreamState.idle;
    case 1: return StreamState.buffering;
    case 2: return StreamState.ready;
    case 3: return StreamState.seeking;
    case 4: return StreamState.error;
    default: return StreamState.idle;
  }
}

/// Convert native integer state to [TorrentState].
TorrentState stateFromInt(int v) {
  switch (v) {
    case -2: return TorrentState.error;
    case  0: return TorrentState.checkingFiles;
    case  1: return TorrentState.downloadingMetadata;
    case  2: return TorrentState.downloading;
    case  3: return TorrentState.finished;
    case  4: return TorrentState.seeding;
    case  5: return TorrentState.allocating;
    case  6: return TorrentState.checkingResume;
    default: return TorrentState.unknown;
  }
}

extension TorrentStateX on TorrentState {
  String get label {
    switch (this) {
      case TorrentState.error:               return 'Error';
      case TorrentState.unknown:             return 'Unknown';
      case TorrentState.checkingFiles:       return 'Checking files';
      case TorrentState.downloadingMetadata: return 'Getting metadata';
      case TorrentState.downloading:         return 'Downloading';
      case TorrentState.finished:            return 'Finished';
      case TorrentState.seeding:             return 'Seeding';
      case TorrentState.allocating:          return 'Allocating';
      case TorrentState.checkingResume:      return 'Checking resume';
    }
  }

  bool get isActive =>
      this == TorrentState.downloading ||
      this == TorrentState.downloadingMetadata ||
      this == TorrentState.allocating ||
      this == TorrentState.checkingFiles ||
      this == TorrentState.checkingResume;

  bool get isDone =>
      this == TorrentState.finished || this == TorrentState.seeding;
}

/// Information about a torrent.
class TorrentInfo {
  final int id;
  final String name;
  final String savePath;
  final String errorMsg;
  final TorrentState state;
  final double progress;
  final int downloadRate;
  final int uploadRate;
  final int totalDone;
  final int totalWanted;
  final int totalUploaded;
  final int numPeers;
  final int numSeeds;
  final bool isPaused;
  final bool isFinished;
  final bool hasMetadata;
  final int queuePosition;

  const TorrentInfo({
    required this.id, required this.name, required this.savePath,
    required this.errorMsg, required this.state, required this.progress,
    required this.downloadRate, required this.uploadRate,
    required this.totalDone, required this.totalWanted,
    required this.totalUploaded, required this.numPeers,
    required this.numSeeds, required this.isPaused,
    required this.isFinished, required this.hasMetadata,
    required this.queuePosition,
  });

  TorrentInfo copyWith({
    String? name, String? savePath, String? errorMsg,
    TorrentState? state, double? progress,
    int? downloadRate, int? uploadRate,
    int? totalDone, int? totalWanted, int? totalUploaded,
    int? numPeers, int? numSeeds,
    bool? isPaused, bool? isFinished, bool? hasMetadata, int? queuePosition,
  }) => TorrentInfo(
    id: id,
    name: name ?? this.name,
    savePath: savePath ?? this.savePath,
    errorMsg: errorMsg ?? this.errorMsg,
    state: state ?? this.state,
    progress: progress ?? this.progress,
    downloadRate: downloadRate ?? this.downloadRate,
    uploadRate: uploadRate ?? this.uploadRate,
    totalDone: totalDone ?? this.totalDone,
    totalWanted: totalWanted ?? this.totalWanted,
    totalUploaded: totalUploaded ?? this.totalUploaded,
    numPeers: numPeers ?? this.numPeers,
    numSeeds: numSeeds ?? this.numSeeds,
    isPaused: isPaused ?? this.isPaused,
    isFinished: isFinished ?? this.isFinished,
    hasMetadata: hasMetadata ?? this.hasMetadata,
    queuePosition: queuePosition ?? this.queuePosition,
  );

  @override
  String toString() => 'TorrentInfo(id=$id, name=$name, state=$state, '
      'progress=${(progress * 100).toStringAsFixed(1)}%)';
}

/// Information about a file within a torrent.
class FileInfo {
  final int index;
  final String name;
  final String path;
  final int size;
  final bool isStreamable;

  const FileInfo({
    required this.index, required this.name, required this.path,
    required this.size, required this.isStreamable,
  });

  @override
  String toString() => 'FileInfo(index=$index, name=$name, '
      'size=$size, streamable=$isStreamable)';
}

/// Information about an active stream.
class StreamInfo {
  final int id;
  final int torrentId;
  final int fileIndex;
  final String url;
  final int fileSize;
  final int readHead;
  final StreamState streamState;
  final double bufferSeconds;
  final int bufferPieces;
  final int readaheadWindow;
  final int activePeers;
  final int downloadRate;

  const StreamInfo({
    required this.id, required this.torrentId, required this.fileIndex,
    required this.url, required this.fileSize, required this.readHead,
    required this.streamState, required this.bufferSeconds,
    required this.bufferPieces, required this.readaheadWindow,
    required this.activePeers, required this.downloadRate,
  });

  bool get isReady => streamState == StreamState.ready;
  bool get isBuffering => streamState == StreamState.buffering;
  bool get isSeeking => streamState == StreamState.seeking;
  bool get isActive => streamState != StreamState.idle && streamState != StreamState.error;

  /// Backward-compatible buffer percentage (0.0–1.0).
  /// Derived from bufferPieces relative to readaheadWindow.
  double get bufferPct => readaheadWindow > 0
      ? (bufferPieces / readaheadWindow).clamp(0.0, 1.0)
      : 0.0;

  @override
  String toString() => 'StreamInfo(id=$id, url=$url, state=$streamState, '
      'buffer=${bufferSeconds.toStringAsFixed(1)}s, peers=$activePeers)';
}

// ─── Formatting Utilities ─────────────────────────────────────────────────────

/// Format [bytes] as a human-readable string (e.g. "1.5 GB").
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  int i = 0;
  double v = bytes.toDouble();
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return '${v.toStringAsFixed(decimals)} ${units[i]}';
}

/// Format bytes-per-second as a speed string.
String formatSpeed(int bps) => '${formatBytes(bps)}/s';

/// Format estimated time remaining for a torrent.
String formatEta(TorrentInfo t) {
  if (t.downloadRate <= 0) return '∞';
  final remaining = t.totalWanted - t.totalDone;
  if (remaining <= 0) return 'Done';
  final secs = remaining ~/ t.downloadRate;
  if (secs < 60) return '${secs}s';
  if (secs < 3600) return '${secs ~/ 60}m ${secs % 60}s';
  return '${secs ~/ 3600}h ${(secs % 3600) ~/ 60}m';
}

// ─── Engine Configuration — port of settings/btsets.go BTSets ────────────────

/// TorrServer-equivalent engine configuration.
///
/// Port of TorrServer's `settings.BTSets` struct. Controls cache, connections,
/// encryption, protocol toggles, rate limits, etc.
class BtConfig {
  /// Cache size in bytes (default 64 MB).
  final int cacheSize;

  /// Percentage of cache used for read-ahead (5–100, default 95).
  final int readerReadAhead;

  /// Percentage of cache preloaded on stream start (0–100, default 50).
  final int preloadCache;

  /// Max concurrent piece requests per reader (default 25).
  final int connectionsLimit;

  /// Seconds of inactivity before a reader-less torrent is paused (default 30).
  final int torrentDisconnectTimeout;

  /// Force encrypted connections only.
  final bool forceEncrypt;

  /// Disable TCP transport (UTP only).
  final bool disableTcp;

  /// Disable UTP transport (TCP only).
  final bool disableUtp;

  /// Disable uploading to other peers.
  final bool disableUpload;

  /// Disable DHT peer discovery.
  final bool disableDht;

  /// Disable UPnP / NAT-PMP port forwarding.
  final bool disableUpnp;

  /// Enable IPv6 listening.
  final bool enableIpv6;

  /// Download rate limit in KB/s (0 = unlimited).
  final int downloadRateLimit;

  /// Upload rate limit in KB/s (0 = unlimited).
  final int uploadRateLimit;

  /// Port for incoming peer connections (0 = default).
  final int peersListenPort;

  /// Enable responsive mode for readers (lower latency, more aggressive).
  final bool responsiveMode;

  const BtConfig({
    this.cacheSize = 64 * 1024 * 1024,
    this.readerReadAhead = 95,
    this.preloadCache = 50,
    this.connectionsLimit = 25,
    this.torrentDisconnectTimeout = 30,
    this.forceEncrypt = false,
    this.disableTcp = false,
    this.disableUtp = false,
    this.disableUpload = false,
    this.disableDht = false,
    this.disableUpnp = false,
    this.enableIpv6 = false,
    this.downloadRateLimit = 0,
    this.uploadRateLimit = 0,
    this.peersListenPort = 0,
    this.responsiveMode = true,
  });

  BtConfig copyWith({
    int? cacheSize,
    int? readerReadAhead,
    int? preloadCache,
    int? connectionsLimit,
    int? torrentDisconnectTimeout,
    bool? forceEncrypt,
    bool? disableTcp,
    bool? disableUtp,
    bool? disableUpload,
    bool? disableDht,
    bool? disableUpnp,
    bool? enableIpv6,
    int? downloadRateLimit,
    int? uploadRateLimit,
    int? peersListenPort,
    bool? responsiveMode,
  }) => BtConfig(
    cacheSize: cacheSize ?? this.cacheSize,
    readerReadAhead: readerReadAhead ?? this.readerReadAhead,
    preloadCache: preloadCache ?? this.preloadCache,
    connectionsLimit: connectionsLimit ?? this.connectionsLimit,
    torrentDisconnectTimeout: torrentDisconnectTimeout ?? this.torrentDisconnectTimeout,
    forceEncrypt: forceEncrypt ?? this.forceEncrypt,
    disableTcp: disableTcp ?? this.disableTcp,
    disableUtp: disableUtp ?? this.disableUtp,
    disableUpload: disableUpload ?? this.disableUpload,
    disableDht: disableDht ?? this.disableDht,
    disableUpnp: disableUpnp ?? this.disableUpnp,
    enableIpv6: enableIpv6 ?? this.enableIpv6,
    downloadRateLimit: downloadRateLimit ?? this.downloadRateLimit,
    uploadRateLimit: uploadRateLimit ?? this.uploadRateLimit,
    peersListenPort: peersListenPort ?? this.peersListenPort,
    responsiveMode: responsiveMode ?? this.responsiveMode,
  );

  @override
  String toString() => 'BtConfig(cache=${cacheSize ~/ (1024 * 1024)}MB, '
      'readAhead=$readerReadAhead%, conns=$connectionsLimit, '
      'encrypt=$forceEncrypt, responsive=$responsiveMode)';
}
