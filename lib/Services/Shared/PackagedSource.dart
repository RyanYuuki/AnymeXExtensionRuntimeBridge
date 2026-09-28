import '../../Models/Source.dart';

abstract class PackagedSource extends Source {
  String? pkgName;
  String? apkName;
  String? apkUrlOverride;
  String? jarUrl;
  String? apkPath;

  PackagedSource({
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
    this.pkgName,
    this.apkName,
    this.apkUrlOverride,
    this.jarUrl,
    this.apkPath,
  });

  String? get apkUrl {
    final override = apkUrlOverride;
    if (override != null && override.isNotEmpty) return override;

    final apk = apkName;
    final icon = iconUrl;
    if (apk == null || apk.isEmpty) return null;
    if (icon == null || icon.isEmpty) return null;

    final base = icon.replaceFirst('icon/', 'apk/');
    final lastSlash = base.lastIndexOf('/');
    if (lastSlash == -1) return '';

    return '${base.substring(0, lastSlash)}/$apk';
  }
}
