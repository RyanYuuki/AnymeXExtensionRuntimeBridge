/// Status enum representing the operational state of a torrent.
enum TorrentStat {
  added(0),
  gettingInfo(1),
  preload(2),
  working(3),
  closed(4),
  inDb(5),
  unknown(-1);

  final int value;
  const TorrentStat(this.value);

  static TorrentStat fromInt(int? value) {
    if (value == null) {
      return TorrentStat.unknown;
    }
    return TorrentStat.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TorrentStat.unknown,
    );
  }
}

/// Statistics for an individual file within a torrent.
class TorrentFileStat {
  final int id;
  final String path;
  final int length;

  const TorrentFileStat({
    required this.id,
    required this.path,
    required this.length,
  });

  factory TorrentFileStat.fromJson(Map<String, dynamic> json) {
    return TorrentFileStat(
      id: json['id'] as int? ?? 0,
      path: json['path'] as String? ?? '',
      length: (json['length'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'path': path, 'length': length};
  }

  @override
  String toString() => 'TorrentFileStat(id: $id, path: $path, length: $length)';
}

/// Complete torrent information and live metrics returned by TorrServer API.
class TorrentInfo {
  final String title;
  final String category;
  final String poster;
  final String data;
  final int timestamp;
  final String name;
  final String hash;
  final String torrsHash;
  final TorrentStat stat;
  final String statString;
  final int loadedSize;
  final int torrentSize;
  final int preloadedBytes;
  final int preloadSize;
  final double downloadSpeed;
  final double uploadSpeed;
  final int totalPeers;
  final int pendingPeers;
  final int activePeers;
  final int connectedSeeders;
  final int halfOpenPeers;
  final int bytesWritten;
  final int bytesWrittenData;
  final int bytesRead;
  final int bytesReadData;
  final int bytesReadUsefulData;
  final int chunksWritten;
  final int chunksRead;
  final int chunksReadUseful;
  final int chunksReadWasted;
  final int piecesDirtiedGood;
  final int piecesDirtiedBad;
  final double durationSeconds;
  final String bitRate;
  final List<TorrentFileStat> fileStats;

  const TorrentInfo({
    required this.title,
    this.category = '',
    this.poster = '',
    this.data = '',
    this.timestamp = 0,
    this.name = '',
    required this.hash,
    this.torrsHash = '',
    this.stat = TorrentStat.unknown,
    this.statString = '',
    this.loadedSize = 0,
    this.torrentSize = 0,
    this.preloadedBytes = 0,
    this.preloadSize = 0,
    this.downloadSpeed = 0.0,
    this.uploadSpeed = 0.0,
    this.totalPeers = 0,
    this.pendingPeers = 0,
    this.activePeers = 0,
    this.connectedSeeders = 0,
    this.halfOpenPeers = 0,
    this.bytesWritten = 0,
    this.bytesWrittenData = 0,
    this.bytesRead = 0,
    this.bytesReadData = 0,
    this.bytesReadUsefulData = 0,
    this.chunksWritten = 0,
    this.chunksRead = 0,
    this.chunksReadUseful = 0,
    this.chunksReadWasted = 0,
    this.piecesDirtiedGood = 0,
    this.piecesDirtiedBad = 0,
    this.durationSeconds = 0.0,
    this.bitRate = '',
    this.fileStats = const [],
  });

  factory TorrentInfo.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['file_stats'] as List<dynamic>?;
    final fileStats = rawFiles != null
        ? rawFiles
              .whereType<Map<String, dynamic>>()
              .map(TorrentFileStat.fromJson)
              .toList()
        : <TorrentFileStat>[];

    return TorrentInfo(
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? '',
      poster: json['poster'] as String? ?? '',
      data: json['data'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      hash: json['hash'] as String? ?? '',
      torrsHash: json['torrs_hash'] as String? ?? '',
      stat: TorrentStat.fromInt(json['stat'] as int?),
      statString: json['stat_string'] as String? ?? '',
      loadedSize: (json['loaded_size'] as num?)?.toInt() ?? 0,
      torrentSize: (json['torrent_size'] as num?)?.toInt() ?? 0,
      preloadedBytes: (json['preloaded_bytes'] as num?)?.toInt() ?? 0,
      preloadSize: (json['preload_size'] as num?)?.toInt() ?? 0,
      downloadSpeed: (json['download_speed'] as num?)?.toDouble() ?? 0.0,
      uploadSpeed: (json['upload_speed'] as num?)?.toDouble() ?? 0.0,
      totalPeers: (json['total_peers'] as num?)?.toInt() ?? 0,
      pendingPeers: (json['pending_peers'] as num?)?.toInt() ?? 0,
      activePeers: (json['active_peers'] as num?)?.toInt() ?? 0,
      connectedSeeders: (json['connected_seeders'] as num?)?.toInt() ?? 0,
      halfOpenPeers: (json['half_open_peers'] as num?)?.toInt() ?? 0,
      bytesWritten: (json['bytes_written'] as num?)?.toInt() ?? 0,
      bytesWrittenData: (json['bytes_written_data'] as num?)?.toInt() ?? 0,
      bytesRead: (json['bytes_read'] as num?)?.toInt() ?? 0,
      bytesReadData: (json['bytes_read_data'] as num?)?.toInt() ?? 0,
      bytesReadUsefulData:
          (json['bytes_read_useful_data'] as num?)?.toInt() ?? 0,
      chunksWritten: (json['chunks_written'] as num?)?.toInt() ?? 0,
      chunksRead: (json['chunks_read'] as num?)?.toInt() ?? 0,
      chunksReadUseful: (json['chunks_read_useful'] as num?)?.toInt() ?? 0,
      chunksReadWasted: (json['chunks_read_wasted'] as num?)?.toInt() ?? 0,
      piecesDirtiedGood: (json['pieces_dirtied_good'] as num?)?.toInt() ?? 0,
      piecesDirtiedBad: (json['pieces_dirtied_bad'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0.0,
      bitRate: json['bit_rate'] as String? ?? '',
      fileStats: fileStats,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'category': category,
      'poster': poster,
      if (data.isNotEmpty) 'data': data,
      'timestamp': timestamp,
      if (name.isNotEmpty) 'name': name,
      'hash': hash,
      if (torrsHash.isNotEmpty) 'torrs_hash': torrsHash,
      'stat': stat.value,
      'stat_string': statString,
      'loaded_size': loadedSize,
      'torrent_size': torrentSize,
      'preloaded_bytes': preloadedBytes,
      'preload_size': preloadSize,
      'download_speed': downloadSpeed,
      'upload_speed': uploadSpeed,
      'total_peers': totalPeers,
      'pending_peers': pendingPeers,
      'active_peers': activePeers,
      'connected_seeders': connectedSeeders,
      'half_open_peers': halfOpenPeers,
      'bytes_written': bytesWritten,
      'bytes_written_data': bytesWrittenData,
      'bytes_read': bytesRead,
      'bytes_read_data': bytesReadData,
      'bytes_read_useful_data': bytesReadUsefulData,
      'chunks_written': chunksWritten,
      'chunks_read': chunksRead,
      'chunks_read_useful': chunksReadUseful,
      'chunks_read_wasted': chunksReadWasted,
      'pieces_dirtied_good': piecesDirtiedGood,
      'pieces_dirtied_bad': piecesDirtiedBad,
      'duration_seconds': durationSeconds,
      if (bitRate.isNotEmpty) 'bit_rate': bitRate,
      'file_stats': fileStats.map((f) => f.toJson()).toList(),
    };
  }

  @override
  String toString() =>
      'TorrentInfo(hash: $hash, title: $title, stat: $statString, activePeers: $activePeers)';
}
