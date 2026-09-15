package android.content.pm

import android.os.Bundle

class PackageManager {

    private val packages = mutableMapOf<String, PackageInfo>()

    fun registerPackage(info: PackageInfo) {
        packages[info.packageName] = info
    }

    fun getPackageInfo(packageName: String, flags: Int): PackageInfo =
        packages[packageName] ?: PackageInfo().apply { this.packageName = packageName }

    fun getApplicationInfo(packageName: String, flags: Int): ApplicationInfo =
        getPackageInfo(packageName, flags).applicationInfo ?: ApplicationInfo().apply {
            this.packageName = packageName
            sourceDir = System.getProperty("user.home")
        }

    fun getInstalledPackages(flags: Int): List<PackageInfo> = packages.values.toList()

    fun getLaunchIntentForPackage(packageName: String): Any? = null

    fun queryIntentActivities(intent: Any?, flags: Int): List<ResolveInfo> = emptyList()

    fun getApplicationLabel(info: ApplicationInfo): CharSequence = info.packageName
}

class PackageInfo {
    var packageName: String = ""
    var versionName: String? = null
    var versionCode: Int = 0
    var applicationInfo: ApplicationInfo? = null
    var signatures: Array<Signature>? = null
    var sourceDir: String? = null
}

class ApplicationInfo {
    var packageName: String = ""
    var sourceDir: String? = null
    var publicSourceDir: String? = null
    var dataDir: String? = null
    var metaData: Bundle? = null
    var uid: Int = 1000
    var targetSdkVersion: Int = 33
    var minSdkVersion: Int = 21
    var flags: Int = 0

    fun loadIcon(pm: PackageManager): Any? = null
    fun loadLabel(pm: PackageManager): CharSequence = packageName
}

class Signature(val toByteArray: ByteArray)

class ResolveInfo {
    var activityInfo: Any? = null
    var resolvePackageName: String? = null
}
