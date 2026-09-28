/// Configuration for TMDB metadata provider in TorrServer.
class TMDBConfig {
  final String apiKey;
  final String apiUrl;
  final String imageUrl;
  final String imageUrlRu;

  const TMDBConfig({
    this.apiKey = '',
    this.apiUrl = 'https://api.themoviedb.org',
    this.imageUrl = 'https://image.tmdb.org',
    this.imageUrlRu = 'https://imagetmdb.com',
  });

  factory TMDBConfig.fromJson(Map<String, dynamic> json) {
    return TMDBConfig(
      apiKey: json['APIKey'] as String? ?? json['apiKey'] as String? ?? '',
      apiUrl:
          json['APIURL'] as String? ??
          json['apiUrl'] as String? ??
          'https://api.themoviedb.org',
      imageUrl:
          json['ImageURL'] as String? ??
          json['imageUrl'] as String? ??
          'https://image.tmdb.org',
      imageUrlRu:
          json['ImageURLRu'] as String? ??
          json['imageUrlRu'] as String? ??
          'https://imagetmdb.com',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'APIKey': apiKey,
      'APIURL': apiUrl,
      'ImageURL': imageUrl,
      'ImageURLRu': imageUrlRu,
    };
  }
}

/// Configuration for Torznab tracker provider.
class TorznabConfig {
  final String host;
  final String key;
  final String name;

  const TorznabConfig({required this.host, this.key = '', this.name = ''});

  factory TorznabConfig.fromJson(Map<String, dynamic> json) {
    return TorznabConfig(
      host: json['Host'] as String? ?? json['host'] as String? ?? '',
      key: json['Key'] as String? ?? json['key'] as String? ?? '',
      name: json['Name'] as String? ?? json['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'Host': host, 'Key': key, 'Name': name};
  }
}

/// Complete configuration settings for TorrServer (`BTSets`), with documented defaults.
class TorrServerSettings {
  // Cache
  final int cacheSize; // in bytes, default 64 MB (67108864)
  final int readerReadAHead; // in percent, default 95
  final int preloadCache; // in percent, default 50

  // Disk
  final bool useDisk;
  final String torrentsSavePath;
  final bool removeCacheOnDrop;

  // Torrent
  final bool forceEncrypt;
  final int
  retrackersMode; // 0 - don't add, 1 - add (default), 2 - remove, 3 - replace
  final int torrentDisconnectTimeout; // in seconds, default 30
  final bool enableDebug;

  // DLNA & Bonjour
  final bool enableDLNA;
  final bool enableBonjour;
  final String friendlyName;

  // Search providers
  final bool enableRutorSearch;
  final bool enableTorznabSearch;
  final List<TorznabConfig> torznabUrls;
  final TMDBConfig tmdbSettings;

  // BitTorrent Network
  final bool enableIPv6;
  final bool disableTCP;
  final bool disableUTP;
  final bool disableUPNP;
  final bool disableDHT;
  final bool disablePEX;
  final bool disableUpload;
  final int downloadRateLimit; // in KB/s, 0 - unlimited
  final int uploadRateLimit; // in KB/s, 0 - unlimited
  final int connectionsLimit; // default 25
  final int peersListenPort;

  // LPD (Local Peer Discovery)
  final bool enableLPD; // default true
  final bool lpdIPv6; // default false

  // HTTPS
  final int sslPort;
  final String sslCert;
  final String sslKey;

  // Reader & Filesystem
  final bool responsiveMode; // default true
  final bool showFSActiveTorr; // default true

  // Storage preferences
  final bool storeSettingsInJson; // default true
  final bool storeViewedInJson; // default false
  final bool trackTimecode;

  const TorrServerSettings({
    this.cacheSize = 64 * 1024 * 1024,
    this.readerReadAHead = 95,
    this.preloadCache = 50,
    this.useDisk = false,
    this.torrentsSavePath = '',
    this.removeCacheOnDrop = false,
    this.forceEncrypt = false,
    this.retrackersMode = 1,
    this.torrentDisconnectTimeout = 30,
    this.enableDebug = false,
    this.enableDLNA = false,
    this.enableBonjour = true,
    this.friendlyName = '',
    this.enableRutorSearch = false,
    this.enableTorznabSearch = false,
    this.torznabUrls = const [],
    this.tmdbSettings = const TMDBConfig(),
    this.enableIPv6 = false,
    this.disableTCP = false,
    this.disableUTP = false,
    this.disableUPNP = false,
    this.disableDHT = false,
    this.disablePEX = false,
    this.disableUpload = false,
    this.downloadRateLimit = 0,
    this.uploadRateLimit = 0,
    this.connectionsLimit = 25,
    this.peersListenPort = 0,
    this.enableLPD = true,
    this.lpdIPv6 = false,
    this.sslPort = 0,
    this.sslCert = '',
    this.sslKey = '',
    this.responsiveMode = true,
    this.showFSActiveTorr = true,
    this.storeSettingsInJson = true,
    this.storeViewedInJson = false,
    this.trackTimecode = false,
  });

  factory TorrServerSettings.fromJson(Map<String, dynamic> json) {
    final rawTorznab =
        json['TorznabUrls'] as List<dynamic>? ??
        json['torznabUrls'] as List<dynamic>?;
    final torznabUrls = rawTorznab != null
        ? rawTorznab
              .whereType<Map<String, dynamic>>()
              .map(TorznabConfig.fromJson)
              .toList()
        : <TorznabConfig>[];

    final rawTmdb =
        json['TMDBSettings'] as Map<String, dynamic>? ??
        json['tmdbSettings'] as Map<String, dynamic>?;
    final tmdbSettings = rawTmdb != null
        ? TMDBConfig.fromJson(rawTmdb)
        : const TMDBConfig();

    return TorrServerSettings(
      cacheSize: (json['CacheSize'] as num?)?.toInt() ?? 64 * 1024 * 1024,
      readerReadAHead: (json['ReaderReadAHead'] as num?)?.toInt() ?? 95,
      preloadCache: (json['PreloadCache'] as num?)?.toInt() ?? 50,
      useDisk: json['UseDisk'] as bool? ?? false,
      torrentsSavePath: json['TorrentsSavePath'] as String? ?? '',
      removeCacheOnDrop: json['RemoveCacheOnDrop'] as bool? ?? false,
      forceEncrypt: json['ForceEncrypt'] as bool? ?? false,
      retrackersMode: (json['RetrackersMode'] as num?)?.toInt() ?? 1,
      torrentDisconnectTimeout:
          (json['TorrentDisconnectTimeout'] as num?)?.toInt() ?? 30,
      enableDebug: json['EnableDebug'] as bool? ?? false,
      enableDLNA: json['EnableDLNA'] as bool? ?? false,
      enableBonjour: json['EnableBonjour'] as bool? ?? true,
      friendlyName: json['FriendlyName'] as String? ?? '',
      enableRutorSearch: json['EnableRutorSearch'] as bool? ?? false,
      enableTorznabSearch: json['EnableTorznabSearch'] as bool? ?? false,
      torznabUrls: torznabUrls,
      tmdbSettings: tmdbSettings,
      enableIPv6: json['EnableIPv6'] as bool? ?? false,
      disableTCP: json['DisableTCP'] as bool? ?? false,
      disableUTP: json['DisableUTP'] as bool? ?? false,
      disableUPNP: json['DisableUPNP'] as bool? ?? false,
      disableDHT: json['DisableDHT'] as bool? ?? false,
      disablePEX: json['DisablePEX'] as bool? ?? false,
      disableUpload: json['DisableUpload'] as bool? ?? false,
      downloadRateLimit: (json['DownloadRateLimit'] as num?)?.toInt() ?? 0,
      uploadRateLimit: (json['UploadRateLimit'] as num?)?.toInt() ?? 0,
      connectionsLimit: (json['ConnectionsLimit'] as num?)?.toInt() ?? 25,
      peersListenPort: (json['PeersListenPort'] as num?)?.toInt() ?? 0,
      enableLPD: json['EnableLPD'] as bool? ?? true,
      lpdIPv6: json['LPDIPv6'] as bool? ?? false,
      sslPort: (json['SslPort'] as num?)?.toInt() ?? 0,
      sslCert: json['SslCert'] as String? ?? '',
      sslKey: json['SslKey'] as String? ?? '',
      responsiveMode: json['ResponsiveMode'] as bool? ?? true,
      showFSActiveTorr: json['ShowFSActiveTorr'] as bool? ?? true,
      storeSettingsInJson: json['StoreSettingsInJson'] as bool? ?? true,
      storeViewedInJson: json['StoreViewedInJson'] as bool? ?? false,
      trackTimecode: json['TrackTimecode'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'CacheSize': cacheSize,
      'ReaderReadAHead': readerReadAHead,
      'PreloadCache': preloadCache,
      'UseDisk': useDisk,
      'TorrentsSavePath': torrentsSavePath,
      'RemoveCacheOnDrop': removeCacheOnDrop,
      'ForceEncrypt': forceEncrypt,
      'RetrackersMode': retrackersMode,
      'TorrentDisconnectTimeout': torrentDisconnectTimeout,
      'EnableDebug': enableDebug,
      'EnableDLNA': enableDLNA,
      'EnableBonjour': enableBonjour,
      'FriendlyName': friendlyName,
      'EnableRutorSearch': enableRutorSearch,
      'EnableTorznabSearch': enableTorznabSearch,
      'TorznabUrls': torznabUrls.map((e) => e.toJson()).toList(),
      'TMDBSettings': tmdbSettings.toJson(),
      'EnableIPv6': enableIPv6,
      'DisableTCP': disableTCP,
      'DisableUTP': disableUTP,
      'DisableUPNP': disableUPNP,
      'DisableDHT': disableDHT,
      'DisablePEX': disablePEX,
      'DisableUpload': disableUpload,
      'DownloadRateLimit': downloadRateLimit,
      'UploadRateLimit': uploadRateLimit,
      'ConnectionsLimit': connectionsLimit,
      'PeersListenPort': peersListenPort,
      'EnableLPD': enableLPD,
      'LPDIPv6': lpdIPv6,
      'SslPort': sslPort,
      'SslCert': sslCert,
      'SslKey': sslKey,
      'ResponsiveMode': responsiveMode,
      'ShowFSActiveTorr': showFSActiveTorr,
      'StoreSettingsInJson': storeSettingsInJson,
      'StoreViewedInJson': storeViewedInJson,
      'TrackTimecode': trackTimecode,
    };
  }

  TorrServerSettings copyWith({
    int? cacheSize,
    int? readerReadAHead,
    int? preloadCache,
    bool? useDisk,
    String? torrentsSavePath,
    bool? removeCacheOnDrop,
    bool? forceEncrypt,
    int? retrackersMode,
    int? torrentDisconnectTimeout,
    bool? enableDebug,
    bool? enableDLNA,
    bool? enableBonjour,
    String? friendlyName,
    bool? enableRutorSearch,
    bool? enableTorznabSearch,
    List<TorznabConfig>? torznabUrls,
    TMDBConfig? tmdbSettings,
    bool? enableIPv6,
    bool? disableTCP,
    bool? disableUTP,
    bool? disableUPNP,
    bool? disableDHT,
    bool? disablePEX,
    bool? disableUpload,
    int? downloadRateLimit,
    int? uploadRateLimit,
    int? connectionsLimit,
    int? peersListenPort,
    bool? enableLPD,
    bool? lpdIPv6,
    int? sslPort,
    String? sslCert,
    String? sslKey,
    bool? responsiveMode,
    bool? showFSActiveTorr,
    bool? storeSettingsInJson,
    bool? storeViewedInJson,
    bool? trackTimecode,
  }) {
    return TorrServerSettings(
      cacheSize: cacheSize ?? this.cacheSize,
      readerReadAHead: readerReadAHead ?? this.readerReadAHead,
      preloadCache: preloadCache ?? this.preloadCache,
      useDisk: useDisk ?? this.useDisk,
      torrentsSavePath: torrentsSavePath ?? this.torrentsSavePath,
      removeCacheOnDrop: removeCacheOnDrop ?? this.removeCacheOnDrop,
      forceEncrypt: forceEncrypt ?? this.forceEncrypt,
      retrackersMode: retrackersMode ?? this.retrackersMode,
      torrentDisconnectTimeout:
          torrentDisconnectTimeout ?? this.torrentDisconnectTimeout,
      enableDebug: enableDebug ?? this.enableDebug,
      enableDLNA: enableDLNA ?? this.enableDLNA,
      enableBonjour: enableBonjour ?? this.enableBonjour,
      friendlyName: friendlyName ?? this.friendlyName,
      enableRutorSearch: enableRutorSearch ?? this.enableRutorSearch,
      enableTorznabSearch: enableTorznabSearch ?? this.enableTorznabSearch,
      torznabUrls: torznabUrls ?? this.torznabUrls,
      tmdbSettings: tmdbSettings ?? this.tmdbSettings,
      enableIPv6: enableIPv6 ?? this.enableIPv6,
      disableTCP: disableTCP ?? this.disableTCP,
      disableUTP: disableUTP ?? this.disableUTP,
      disableUPNP: disableUPNP ?? this.disableUPNP,
      disableDHT: disableDHT ?? this.disableDHT,
      disablePEX: disablePEX ?? this.disablePEX,
      disableUpload: disableUpload ?? this.disableUpload,
      downloadRateLimit: downloadRateLimit ?? this.downloadRateLimit,
      uploadRateLimit: uploadRateLimit ?? this.uploadRateLimit,
      connectionsLimit: connectionsLimit ?? this.connectionsLimit,
      peersListenPort: peersListenPort ?? this.peersListenPort,
      enableLPD: enableLPD ?? this.enableLPD,
      lpdIPv6: lpdIPv6 ?? this.lpdIPv6,
      sslPort: sslPort ?? this.sslPort,
      sslCert: sslCert ?? this.sslCert,
      sslKey: sslKey ?? this.sslKey,
      responsiveMode: responsiveMode ?? this.responsiveMode,
      showFSActiveTorr: showFSActiveTorr ?? this.showFSActiveTorr,
      storeSettingsInJson: storeSettingsInJson ?? this.storeSettingsInJson,
      storeViewedInJson: storeViewedInJson ?? this.storeViewedInJson,
      trackTimecode: trackTimecode ?? this.trackTimecode,
    );
  }
}
