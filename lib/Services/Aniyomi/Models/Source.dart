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
    return ASource(
      id: json['id']?.toString(),
      name: json['name'],
      baseUrl: json['baseUrl'],
      lang: json['lang'],
      iconUrl: json['iconUrl'],
      isNsfw: json['isNsfw'],
      version: json['version'],
      versionLast: json['versionLast'],
      repo: json['repo'],
      hasUpdate: json['hasUpdate'] ?? false,
      isPrivate: json['isPrivate'] ?? (json['isShared'] != null ? !(json['isShared'] as bool) : null),
      supportsLatest: json['supportsLatest'] ?? false,
      supportsPopular: json['supportsPopular'] ?? false,
      itemType: ItemType.values[json['itemType'] ?? 0],
      pkgName: json['pkgName'],
      apkName: json['apkName'],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = super.toJson();
    map['apkUrl'] = apkName;
    map['pkgName'] = pkgName;
    return map;
  }

  String? get apkUrl {
    if (apkName == null || apkName!.isEmpty) return null;

    if (repo != null && repo!.startsWith('http')) {
      final baseRepoUrl = repo!
          .replaceAll('/index.min.json', '')
          .replaceAll('/index.pb.gz', '')
          .replaceAll('/index.pb', '');
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
