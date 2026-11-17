import '../../../Models/Source.dart';

class ASource extends Source {
  String? pkgName;
  String? apkName;
  List<ASource>? langs;

  ASource({
    super.id,
    super.name,
    super.baseUrl,
    super.lang,
    super.isNsfw,
    super.iconUrl,
    super.version,
    super.versionLast,
    super.itemType,
    super.repo,
    super.hasUpdate,
    super.isPrivate,
    super.supportsLatest,
    super.supportsPopular,
    this.pkgName,
    this.apkName,
  });
  factory ASource.fromJson(Map<String, dynamic> json) {
    final rawLang = json['lang'];
    final parsedLang = rawLang is List
        ? rawLang.map((e) => e.toString()).join(',')
        : rawLang?.toString();
    final rawItemType = json['itemType'];
    final itemTypeIndex = rawItemType is int
        ? rawItemType
        : int.tryParse(rawItemType?.toString() ?? '') ?? 0;

    return ASource(
      id: json['id']?.toString(),
      name: json['name']?.toString(),
      baseUrl: json['baseUrl']?.toString(),
      lang: parsedLang,
      iconUrl: json['iconUrl']?.toString(),
      isNsfw: json['isNsfw'] as bool? ?? false,
      version: json['version']?.toString(),
      versionLast: json['versionLast']?.toString(),
      repo: json['repo']?.toString(),
      hasUpdate: json['hasUpdate'] ?? false,
      isPrivate: json['isPrivate'] ??
          (json['isShared'] != null ? !(json['isShared'] as bool) : null),
      supportsLatest: json['supportsLatest'] ?? false,
      supportsPopular: json['supportsPopular'] ?? false,
      itemType: ItemType.values[itemTypeIndex.clamp(0, ItemType.values.length - 1)],
      pkgName: json['pkgName']?.toString(),
      apkName: (json['apkName'] ?? json['apkUrl'])?.toString(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['apkName'] = apkName;
    map['apkUrl'] = apkName;
    map['pkgName'] = pkgName;
    return map;
  }

  String? get apkUrl {
    if (apkName == null || apkName!.isEmpty) return null;
    if (apkName!.startsWith('http://') || apkName!.startsWith('https://')) {
      return apkName;
    }

    if (repo != null && repo!.startsWith('http')) {
      var baseRepoUrl = repo!
          .replaceAll('/index.min.json', '')
          .replaceAll('/index.json', '')
          .replaceAll('/index.pb.gz', '')
          .replaceAll('/index.pb', '');
      if (baseRepoUrl.endsWith('/')) {
        baseRepoUrl = baseRepoUrl.substring(0, baseRepoUrl.length - 1);
      }
      return '$baseRepoUrl/apk/$apkName';
    }

    if (iconUrl != null && iconUrl!.startsWith('http')) {
      final baseUrl = iconUrl!.replaceFirst('icon/', 'apk/');
      final lastSlash = baseUrl.lastIndexOf('/');
      if (lastSlash == -1) return "";

      final cleanedUrl = baseUrl.substring(0, lastSlash);
      return '$cleanedUrl/$apkName';
    }

    return null;
  }

  @override
  String get uniqueId => '${id}_$pkgName';
}
