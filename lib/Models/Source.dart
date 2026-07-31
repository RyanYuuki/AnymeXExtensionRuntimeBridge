class Source {
  String? id;
  String? name;
  String? baseUrl;
  String? lang;
  bool? isNsfw;
  String? iconUrl;
  String? version;
  String? versionLast;
  ItemType? itemType;
  String? repo;
  String? managerId;
  bool? hasUpdate;
  bool? isPrivate;
  bool? supportsLatest;
  bool? supportsPopular;

  Source({
    this.id = '',
    this.name = '',
    this.baseUrl = '',
    this.lang = '',
    this.iconUrl = '',
    this.isNsfw = false,
    this.version = "0.0.1",
    this.versionLast = "0.0.1",
    this.itemType = ItemType.manga,
    this.repo,
    this.managerId,
    this.hasUpdate = false,
    this.isPrivate,
    this.supportsLatest = false,
    this.supportsPopular = false,
  });

  Source.fromJson(Map<String, dynamic> json) {
    baseUrl = json['baseUrl'] ?? json['site'];
    iconUrl = json['iconUrl'];
    id = json['id'].toString();
    isNsfw = json['isNsfw'];
    lang = json['lang'];
    name = json['name'];
    version = json['version'];
    versionLast = json['versionLast'];
    repo = json['repo'];
    managerId = json['managerId'];
    hasUpdate = json['hasUpdate'] ?? false;
    isPrivate = json['isPrivate'] ?? (json['isShared'] != null ? !(json['isShared'] as bool) : null);
    supportsLatest = json['supportsLatest'] ?? false;
    supportsPopular = json['supportsPopular'] ?? false;

    final isLnReader = json['site'] != null && json['url'] != null && json['sourceCodeLanguage'] == null;
    if (isLnReader) {
      itemType = ItemType.novel;
    } else {
      itemType = ItemType.values[json['itemType'] ?? 0];
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'lang': lang,
        'iconUrl': iconUrl,
        'isNsfw': isNsfw,
        'version': version,
        'versionLast': versionLast,
        'itemType': itemType?.index ?? 0,
        'repo': repo,
        'managerId': managerId,
        'hasUpdate': hasUpdate,
        'isPrivate': isPrivate,
        'supportsLatest': supportsLatest,
        'supportsPopular': supportsPopular,
      };

  String get uniqueId => id ?? '';
}

enum ItemType {
  manga,
  anime,
  novel;

  @override
  String toString() {
    switch (this) {
      case ItemType.manga:
        return 'Manga';
      case ItemType.anime:
        return 'Anime';
      case ItemType.novel:
        return 'Novel';
    }
  }
}
