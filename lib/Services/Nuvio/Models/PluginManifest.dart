class PluginManifest {
  final String name;
  final String version;
  final String? description;
  final String? author;
  final List<PluginScraper> scrapers;
  final String repositoryUrl;

  PluginManifest({
    required this.name,
    required this.version,
    this.description,
    this.author,
    this.scrapers = const [],
    this.repositoryUrl = '',
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json, {String repositoryUrl = ''}) {
    final rawScrapers = json['scrapers'] as List? ?? [];
    final scrapers = rawScrapers
        .whereType<Map>()
        .map((m) => PluginScraper.fromJson(Map<String, dynamic>.from(m), repositoryUrl: repositoryUrl))
        .toList();

    return PluginManifest(
      name: json['name']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0.0',
      description: json['description']?.toString(),
      author: json['author']?.toString(),
      scrapers: scrapers,
      repositoryUrl: repositoryUrl.isNotEmpty ? repositoryUrl : (json['repositoryUrl']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'version': version,
        if (description != null) 'description': description,
        if (author != null) 'author': author,
        'scrapers': scrapers.map((s) => s.toJson()).toList(),
        'repositoryUrl': repositoryUrl,
      };
}

class PluginScraper {
  final String id;
  final String name;
  final String? description;
  final String version;
  final String filename;
  final List<String> supportedTypes;
  final bool enabled;
  final bool hasSettings;
  final String? logo;
  final List<String> contentLanguage;
  final List<String>? supportedPlatforms;
  final List<String>? disabledPlatforms;
  final List<String>? formats;
  final String repositoryUrl;
  String? sourceUrl;
  final List<PluginSettingField> settings;
  String? code;

  List<String> get supportedMedia => supportedTypes;

  PluginScraper({
    required this.id,
    required this.name,
    this.description,
    required this.version,
    required this.filename,
    this.supportedTypes = const ['movie', 'tv'],
    this.enabled = true,
    this.hasSettings = false,
    this.logo,
    this.contentLanguage = const [],
    this.supportedPlatforms,
    this.disabledPlatforms,
    this.formats,
    this.repositoryUrl = '',
    this.sourceUrl,
    this.settings = const [],
    this.code,
  });

  bool supportsType(String type) {
    final norm = type.toLowerCase() == 'series' ? 'tv' : type.toLowerCase();
    return supportedTypes.map((t) => t.toLowerCase() == 'series' ? 'tv' : t.toLowerCase()).contains(norm);
  }

  factory PluginScraper.fromJson(Map<String, dynamic> json, {String repositoryUrl = ''}) {
    final rawSettings = json['settings'] as List? ?? [];
    final parsedSettings = rawSettings
        .whereType<Map>()
        .map((m) => PluginSettingField.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    return PluginScraper(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      version: json['version']?.toString() ?? '1.0.0',
      filename: json['filename']?.toString() ?? '',
      supportedTypes: (json['supportedTypes'] as List?)?.map((e) => e.toString()).toList() ??
          (json['supportedMedia'] as List?)?.map((e) => e.toString()).toList() ??
          ['movie', 'tv'],
      enabled: json['enabled'] != false,
      hasSettings: json['hasSettings'] == true || parsedSettings.isNotEmpty,
      logo: json['logo']?.toString(),
      contentLanguage: (json['contentLanguage'] as List?)?.map((e) => e.toString()).toList() ?? [],
      supportedPlatforms: (json['supportedPlatforms'] as List?)?.map((e) => e.toString()).toList(),
      disabledPlatforms: (json['disabledPlatforms'] as List?)?.map((e) => e.toString()).toList(),
      formats: (json['formats'] as List?)?.map((e) => e.toString()).toList(),
      repositoryUrl: repositoryUrl.isNotEmpty ? repositoryUrl : (json['repositoryUrl']?.toString() ?? ''),
      sourceUrl: json['sourceUrl']?.toString() ?? json['url']?.toString(),
      settings: parsedSettings,
      code: json['code']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'version': version,
        'filename': filename,
        'supportedTypes': supportedTypes,
        'enabled': enabled,
        'hasSettings': hasSettings,
        if (logo != null) 'logo': logo,
        'contentLanguage': contentLanguage,
        if (supportedPlatforms != null) 'supportedPlatforms': supportedPlatforms,
        if (disabledPlatforms != null) 'disabledPlatforms': disabledPlatforms,
        if (formats != null) 'formats': formats,
        'repositoryUrl': repositoryUrl,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        'settings': settings.map((s) => s.toJson()).toList(),
        if (code != null) 'code': code,
      };
}

class PluginRuntimeResult {
  final String title;
  final String? name;
  final String url;
  final String? quality;
  final String? size;
  final String? language;
  final String? provider;
  final String? type;
  final int? seeders;
  final int? peers;
  final String? infoHash;
  final Map<String, String>? headers;
  final List<PluginSubtitleResult>? subtitles;

  PluginRuntimeResult({
    required this.title,
    this.name,
    required this.url,
    this.quality,
    this.size,
    this.language,
    this.provider,
    this.type,
    this.seeders,
    this.peers,
    this.infoHash,
    this.headers,
    this.subtitles,
  });

  factory PluginRuntimeResult.fromJson(Map<String, dynamic> json) {
    Map<String, String>? parsedHeaders;
    if (json['headers'] is Map) {
      parsedHeaders = (json['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    List<PluginSubtitleResult>? parsedSubs;
    if (json['subtitles'] is List) {
      parsedSubs = (json['subtitles'] as List)
          .whereType<Map>()
          .map((m) => PluginSubtitleResult.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    return PluginRuntimeResult(
      title: json['title']?.toString() ?? json['name']?.toString() ?? 'Stream',
      name: json['name']?.toString(),
      url: json['url']?.toString() ?? '',
      quality: json['quality']?.toString(),
      size: json['size']?.toString(),
      language: json['language']?.toString(),
      provider: json['provider']?.toString(),
      type: json['type']?.toString(),
      seeders: int.tryParse(json['seeders']?.toString() ?? ''),
      peers: int.tryParse(json['peers']?.toString() ?? ''),
      infoHash: json['infoHash']?.toString().toLowerCase(),
      headers: parsedHeaders,
      subtitles: parsedSubs,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        if (name != null) 'name': name,
        'url': url,
        if (quality != null) 'quality': quality,
        if (size != null) 'size': size,
        if (language != null) 'language': language,
        if (provider != null) 'provider': provider,
        if (type != null) 'type': type,
        if (seeders != null) 'seeders': seeders,
        if (peers != null) 'peers': peers,
        if (infoHash != null) 'infoHash': infoHash,
        if (headers != null) 'headers': headers,
        if (subtitles != null) 'subtitles': subtitles!.map((s) => s.toJson()).toList(),
      };
}

class PluginSubtitleResult {
  final String url;
  final String language;
  final String? name;
  final Map<String, String>? headers;

  PluginSubtitleResult({
    required this.url,
    required this.language,
    this.name,
    this.headers,
  });

  factory PluginSubtitleResult.fromJson(Map<String, dynamic> json) {
    Map<String, String>? parsedHeaders;
    if (json['headers'] is Map) {
      parsedHeaders = (json['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    return PluginSubtitleResult(
      url: json['url']?.toString() ?? '',
      language: json['language']?.toString() ?? 'Unknown',
      name: json['name']?.toString(),
      headers: parsedHeaders,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'language': language,
        if (name != null) 'name': name,
        if (headers != null) 'headers': headers,
      };
}

class PluginSettingField {
  final String type;
  final String key;
  final String label;
  final String? description;
  final String? placeholder;
  final bool isPassword;
  final List<Map<String, String>> options;
  final dynamic defaultValue;

  PluginSettingField({
    required this.type,
    required this.key,
    required this.label,
    this.description,
    this.placeholder,
    this.isPassword = false,
    this.options = const [],
    this.defaultValue,
  });

  factory PluginSettingField.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'] as List? ?? [];
    final options = rawOptions.whereType<Map>().map((m) {
      return {
        'label': m['label']?.toString() ?? '',
        'value': m['value']?.toString() ?? '',
      };
    }).toList();

    return PluginSettingField(
      type: json['type']?.toString() ?? 'info',
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      description: json['description']?.toString(),
      placeholder: json['placeholder']?.toString(),
      isPassword: json['isPassword'] == true,
      options: options,
      defaultValue: json['defaultValue'],
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'key': key,
        'label': label,
        if (description != null) 'description': description,
        if (placeholder != null) 'placeholder': placeholder,
        'isPassword': isPassword,
        'options': options,
        if (defaultValue != null) 'defaultValue': defaultValue,
      };
}
