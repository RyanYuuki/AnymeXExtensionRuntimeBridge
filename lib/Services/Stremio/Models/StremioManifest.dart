class StremioManifest {
  final String id;
  final String name;
  final String version;
  final String? description;
  final String? logo;
  final String? background;
  final String? contactEmail;
  final List<String> types;
  final List<StremioManifestResource> resources;
  final List<String>? idPrefixes;
  final List<StremioManifestCatalog> catalogs;
  final List<StremioManifestCatalog> addonCatalogs;
  final List<StremioConfigOption> config;
  final StremioBehaviorHints behaviorHints;
  final String transportUrl;

  StremioManifest({
    required this.id,
    required this.name,
    required this.version,
    this.description,
    this.logo,
    this.background,
    this.contactEmail,
    this.types = const [],
    this.resources = const [],
    this.idPrefixes,
    this.catalogs = const [],
    this.addonCatalogs = const [],
    this.config = const [],
    this.behaviorHints = const StremioBehaviorHints(),
    this.transportUrl = '',
  });

  bool supportsResource(String resourceName, String type, String id) {
    if (resourceName == 'catalog') {
      return catalogs.any((c) => c.type == type);
    }
    if (resourceName == 'addon_catalog') {
      return addonCatalogs.any((c) => c.type == type);
    }

    final matchingResources = resources.where((r) => r.name == resourceName);
    if (matchingResources.isEmpty) return false;

    for (final res in matchingResources) {
      final effectiveTypes = res.types ?? types;
      final typeMatches = effectiveTypes.isEmpty ||
          effectiveTypes.map((t) => t.toLowerCase()).contains(type.toLowerCase()) ||
          (type.toLowerCase() == 'tv' && effectiveTypes.contains('series')) ||
          (type.toLowerCase() == 'series' && effectiveTypes.contains('tv'));

      final effectivePrefixes = res.idPrefixes ?? idPrefixes;
      final idMatches = effectivePrefixes == null ||
          effectivePrefixes.isEmpty ||
          effectivePrefixes.any((prefix) => id.startsWith(prefix));

      if (typeMatches && idMatches) {
        return true;
      }
    }
    return false;
  }

  factory StremioManifest.fromJson(Map<String, dynamic> json, {String transportUrl = ''}) {
    final defaultTypes = (json['types'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final defaultPrefixes = (json['idPrefixes'] as List?)?.map((e) => e.toString()).toList();

    final rawResources = json['resources'] as List? ?? [];
    final resources = rawResources.map<StremioManifestResource>((item) {
      if (item is String) {
        return StremioManifestResource(
          name: item,
          types: defaultTypes,
          idPrefixes: defaultPrefixes,
        );
      } else if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        return StremioManifestResource(
          name: map['name']?.toString() ?? '',
          types: (map['types'] as List?)?.map((e) => e.toString()).toList() ?? defaultTypes,
          idPrefixes: (map['idPrefixes'] as List?)?.map((e) => e.toString()).toList() ?? defaultPrefixes,
        );
      }
      return StremioManifestResource(name: item.toString());
    }).where((r) => r.name.isNotEmpty).toList();

    final rawCatalogs = json['catalogs'] as List? ?? [];
    final catalogs = rawCatalogs.whereType<Map>().map((m) {
      return StremioManifestCatalog.fromJson(Map<String, dynamic>.from(m));
    }).toList();

    final rawAddonCatalogs = json['addonCatalogs'] as List? ?? [];
    final addonCatalogs = rawAddonCatalogs.whereType<Map>().map((m) {
      return StremioManifestCatalog.fromJson(Map<String, dynamic>.from(m));
    }).toList();

    final rawConfig = json['config'] as List? ?? [];
    final config = rawConfig.whereType<Map>().map((m) {
      return StremioConfigOption.fromJson(Map<String, dynamic>.from(m));
    }).toList();

    final hintsMap = json['behaviorHints'] is Map ? Map<String, dynamic>.from(json['behaviorHints']) : null;
    final behaviorHints = hintsMap != null
        ? StremioBehaviorHints.fromJson(hintsMap)
        : const StremioBehaviorHints();

    return StremioManifest(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0.0',
      description: json['description']?.toString(),
      logo: json['logo']?.toString(),
      background: json['background']?.toString(),
      contactEmail: json['contactEmail']?.toString(),
      types: defaultTypes,
      resources: resources,
      idPrefixes: defaultPrefixes,
      catalogs: catalogs,
      addonCatalogs: addonCatalogs,
      config: config,
      behaviorHints: behaviorHints,
      transportUrl: transportUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        if (description != null) 'description': description,
        if (logo != null) 'logo': logo,
        if (background != null) 'background': background,
        if (contactEmail != null) 'contactEmail': contactEmail,
        'types': types,
        'resources': resources.map((r) => r.toJson()).toList(),
        if (idPrefixes != null) 'idPrefixes': idPrefixes,
        'catalogs': catalogs.map((c) => c.toJson()).toList(),
        'addonCatalogs': addonCatalogs.map((c) => c.toJson()).toList(),
        'config': config.map((c) => c.toJson()).toList(),
        'behaviorHints': behaviorHints.toJson(),
        'transportUrl': transportUrl,
      };
}

class StremioManifestResource {
  final String name;
  final List<String>? types;
  final List<String>? idPrefixes;

  StremioManifestResource({
    required this.name,
    this.types,
    this.idPrefixes,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (types != null) 'types': types,
        if (idPrefixes != null) 'idPrefixes': idPrefixes,
      };
}

class StremioManifestCatalog {
  final String type;
  final String id;
  final String name;
  final List<StremioExtraProp> extra;

  StremioManifestCatalog({
    required this.type,
    required this.id,
    required this.name,
    this.extra = const [],
  });

  bool get supportsSearch => extra.any((e) => e.name == 'search');
  bool get requiresSearch => extra.any((e) => e.name == 'search' && e.isRequired);
  bool get supportsSkip => extra.any((e) => e.name == 'skip');
  bool get supportsGenre => extra.any((e) => e.name == 'genre');

  factory StremioManifestCatalog.fromJson(Map<String, dynamic> json) {
    final extraList = <StremioExtraProp>[];

    if (json['extra'] is List) {
      for (final item in (json['extra'] as List)) {
        if (item is Map) {
          extraList.add(StremioExtraProp.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    if (extraList.isEmpty) {
      final supported = (json['extraSupported'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final required = (json['extraRequired'] as List?)?.map((e) => e.toString()).toList() ?? [];
      for (final name in supported) {
        extraList.add(StremioExtraProp(
          name: name,
          isRequired: required.contains(name),
        ));
      }
    }

    return StremioManifestCatalog(
      type: json['type']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['id']?.toString() ?? '',
      extra: extraList,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'name': name,
        'extra': extra.map((e) => e.toJson()).toList(),
      };
}

class StremioExtraProp {
  final String name;
  final bool isRequired;
  final List<String> options;
  final int optionsLimit;

  StremioExtraProp({
    required this.name,
    this.isRequired = false,
    this.options = const [],
    this.optionsLimit = 1,
  });

  factory StremioExtraProp.fromJson(Map<String, dynamic> json) {
    return StremioExtraProp(
      name: json['name']?.toString() ?? '',
      isRequired: json['isRequired'] == true,
      options: (json['options'] as List?)?.map((e) => e.toString()).toList() ?? [],
      optionsLimit: int.tryParse(json['optionsLimit']?.toString() ?? '1') ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'isRequired': isRequired,
        'options': options,
        'optionsLimit': optionsLimit,
      };
}

class StremioConfigOption {
  final String key;
  final String type;
  final String? title;
  final String? defaultValue;
  final List<String> options;
  final bool required;

  StremioConfigOption({
    required this.key,
    required this.type,
    this.title,
    this.defaultValue,
    this.options = const [],
    this.required = false,
  });

  factory StremioConfigOption.fromJson(Map<String, dynamic> json) {
    return StremioConfigOption(
      key: json['key']?.toString() ?? '',
      type: json['type']?.toString() ?? 'text',
      title: json['title']?.toString(),
      defaultValue: json['default']?.toString(),
      options: (json['options'] as List?)?.map((e) => e.toString()).toList() ?? [],
      required: json['required'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type,
        if (title != null) 'title': title,
        if (defaultValue != null) 'default': defaultValue,
        'options': options,
        'required': required,
      };
}

class StremioBehaviorHints {
  final bool adult;
  final bool p2p;
  final bool configurable;
  final bool configurationRequired;
  final bool epgProvider;

  const StremioBehaviorHints({
    this.adult = false,
    this.p2p = false,
    this.configurable = false,
    this.configurationRequired = false,
    this.epgProvider = false,
  });

  factory StremioBehaviorHints.fromJson(Map<String, dynamic> json) {
    return StremioBehaviorHints(
      adult: json['adult'] == true,
      p2p: json['p2p'] == true,
      configurable: json['configurable'] == true,
      configurationRequired: json['configurationRequired'] == true,
      epgProvider: json['epgProvider'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'adult': adult,
        'p2p': p2p,
        'configurable': configurable,
        'configurationRequired': configurationRequired,
        'epgProvider': epgProvider,
      };
}
