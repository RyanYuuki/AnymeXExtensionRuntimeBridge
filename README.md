# AnymeX Extension Runtime Bridge

`anymex_extension_runtime_bridge` is a Flutter plugin providing a **single, unified Dart API** for discovering, installing, managing, and executing content extension sources and streaming addons across Android, iOS, Windows, macOS, and Linux.

Instead of writing custom integrations for each extension format, initialize the bridge once and interact with a unified interface for repositories, installed sources, media details, search, page lists, video streams, novel chapters, and torrent streaming.

---

## Supported Backends & Formats

- **Mangayomi** — JavaScript/Dart extension scripts (anime, manga, novel)
- **Sora** — JavaScript extension modules (anime, manga)
- **Aniyomi** — Tachiyomi-style anime/manga APK/JAR extensions
- **CloudStream** — Video streaming plugins
- **Kotatsu** — Manga extensions (`kotatsu-parsers`)
- **Legado** — 阅读 / Book-source novel extensions & rule engine
- **LnReader** — JavaScript-based novel extensions (QuickJS runtime)
- **Tsundoku** — Novel & manga extensions
- **iReader** — Novel extensions
- **TorrServer Addon** — BitTorrent video streaming engine with caching, HTTP streaming, and torrent file/magnet resolution

---

## Platform Support

| Extension Source | Android | iOS | Windows / Linux / macOS |
|---|:---:|:---:|:---:|
| Mangayomi | ✅ | ✅ | ✅ |
| Sora | ✅ | ✅ | ✅ |
| LnReader | ✅ | ✅ | ✅ |
| Legado | ✅ | ✅ | ✅ |
| Aniyomi | ✅ | ✅ (embedded JVM) | ✅ |
| CloudStream | ✅ | ✅ (embedded JVM) | ✅ |
| Kotatsu | ✅ | ✅ (embedded JVM) | ✅ |
| Tsundoku | ✅ | ✅ (embedded JVM) | ✅ |
| iReader | ✅ | ✅ (embedded JVM) | ✅ |
| TorrServer (`TorrServerAddon`) | ✅ | ✅ (TorrServerKit) | ✅ |

> **Note on iOS:** Sideloading is supported! On iOS, native JVM backends run through an embedded in-process OpenJDK Zero VM (`EmbeddedJvm.mm`), and TorrServer runs via an in-process static Go framework (`TorrServerKit.xcframework`). No subprocesses or JIT required.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      Your Flutter App                            │
│                                                                  │
│  AnymeXExtensionBridge         (Dart plugin)                     │
│  ├─ Mangayomi  ──────────────► Native Dart / JS                  │
│  ├─ Sora       ──────────────► Native Dart / JS                  │
│  ├─ LnReader   ──────────────► Native Dart / QuickJS             │
│  ├─ Legado     ──────────────► Pure Dart Rule Engine             │
│  ├─ Aniyomi    ──────────────► Needs Runtime Bridge              │
│  ├─ CloudStream ─────────────► Needs Runtime Bridge              │
│  ├─ Kotatsu    ──────────────► Needs Runtime Bridge              │
│  ├─ Tsundoku   ──────────────► Needs Runtime Bridge              │
│  ├─ iReader    ──────────────► Needs Runtime Bridge              │
│  └─ TorrServer ──────────────► TorrServerAddon (Subprocess / iOS)│
│                                                                  │
│  AnymeXRuntimeBridge           (Runtime Host)                    │
│  ├─ Android  → Bridge APK (dynamic DEX injection)                │
│  ├─ Desktop  → JRE + Bridge JAR (sidecar process)                │
│  └─ iOS      → OpenJDK Zero VM (in-process JNI)                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### 1. Initialize the Bridge

Call this early in app startup:

```dart
await AnymeXExtensionBridge.init(
  projectName: 'AnymeX',
  getDirectory: myDirectoryResolver,
);
```

### 2. Prepare the Runtime

```dart
await AnymeXRuntimeBridge.checkAndInitialize();

if (!AnymeXRuntimeBridge.controller.isReady.value) {
  await AnymeXRuntimeBridge.setupRuntime();
}

final extManager = Get.find<ExtensionManager>();
await extManager.onRuntimeBridgeInitialization();
```

### 3. Use a Source

Every source exposes a unified `methods` interface:

```dart
final source = extManager.installedAnimeExtensions.first;

final popular = await source.methods.getPopular(1);
final latest  = await source.methods.getLatestUpdates(1);
final results = await source.methods.search('one piece', 1, []);
final details = await source.methods.getDetail(results.list.first);

// For video sources:
final videos = await source.methods.getVideoList(details.episodes.first);

// For novel sources (LnReader, Legado, Tsundoku, iReader):
final text = await source.methods.getNovelContent(
  details.episodes.first.name,
  details.episodes.first.url,
);
```

### 4. Torrent Streaming with TorrServer Addon

```dart
final addon = TorrServerAddon();
await addon.initialize();

if (!addon.installed.value) {
  await addon.install();
}

await addon.start();

final stream = await addon.startStream(
  TorrentStreamRequest(
    torrentUrl: 'magnet:?xt=urn:btih:...',
    fileIndex: 0,
  ),
);

print('Stream video URL: ${stream.streamUrl}');

// Stop stream when done:
await addon.stopStream(stream.hash);
```

---

## Android Host Setup

### 1. Add Required Permissions

In `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
    <uses-permission android:name="android.permission.REQUEST_DELETE_PACKAGES" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />

    <uses-permission
        android:name="android.permission.QUERY_ALL_PACKAGES"
        tools:ignore="QueryAllPackagesPermission" />
    <uses-permission android:name="android.permission.UPDATE_PACKAGES_WITHOUT_USER_ACTION" />

</manifest>
```

### 2. Exclude the Conflicting OSGI Manifest

In `android/app/build.gradle`:

```gradle
android {
    packagingOptions {
        resources {
            exclude 'META-INF/versions/9/OSGI-INF/MANIFEST.MF'
        }
    }
}
```

### 3. Sync and Rebuild

```bash
flutter clean
flutter pub get
flutter build apk
```

---

## iOS Host Setup (Sideloading)

For iOS builds, download and stage the embedded runtimes:

```bash
cd ios
bash PrepareEmbeddedRuntime.sh
bash PrepareTorrServerRuntime.sh
```

---

## API Reference

### `AnymeXExtensionBridge`

| Method | Description |
|---|---|
| `init(...)` | Initialize the bridge (project name, directories, DB) |
| `dispose()` | Clean up resources and stop active bridges |
| `isSupportedPlatform` | Returns `true` if current platform is supported |

### `ExtensionManager`

| Property / Method | Description |
|---|---|
| `installedAnimeExtensions` | Reactive list of installed anime sources |
| `installedMangaExtensions` | Reactive list of installed manga sources |
| `installedNovelExtensions` | Reactive list of installed novel sources |
| `availableAnimeExtensions` | Reactive list of available anime sources |
| `availableMangaExtensions` | Reactive list of available manga sources |
| `availableNovelExtensions` | Reactive list of available novel sources |
| `addRepo(url, type, managerId)` | Add a repository to a specific backend |
| `removeRepo(repo, type)` | Remove a repository |
| `refreshExtensions(...)` | Re-fetch installed and/or available extensions |
| `updateAll()` | Update all sources with pending updates |
| `onRuntimeBridgeInitialization()` | Register bridged extensions after host is loaded |

### `SourceMethods` (Unified Interface)

| Method | Description |
|---|---|
| `getPopular(page)` | Fetch popular items |
| `getLatestUpdates(page)` | Fetch latest updates |
| `search(query, page, filters)` | Search for content |
| `getDetail(media)` | Fetch full detail of an item |
| `getVideoList(episode)` | Fetch video list for an episode |
| `getVideoListStream(episode)` | Stream video results incrementally |
| `getPageList(episode)` | Fetch page list (manga) |
| `getNovelContent(title, id)` | Fetch novel chapter text |
| `getPreference()` | Get extension preferences |
| `setPreference(pref, value)` | Save an extension preference |

### Manager IDs

| `managerId` | Backend | Supported Platforms |
|---|---|---|
| `aniyomi` | Aniyomi extensions | Android, iOS, Desktop |
| `cloudstream` | CloudStream plugins | Android, iOS, Desktop |
| `kotatsu` | Kotatsu extensions | Android, iOS, Desktop |
| `legado` | Legado novel extensions | Android, iOS, Desktop |
| `lnreader` | LnReader novel extensions | Android, iOS, Desktop |
| `tsundoku` | Tsundoku novel/manga extensions | Android, iOS, Desktop |
| `ireader` | iReader novel extensions | Android, iOS, Desktop |
| `mangayomi` | Mangayomi JS extensions | Android, iOS, Desktop |
| `sora` | Sora JS extensions | Android, iOS, Desktop |

---

## Credits & Third-Party Licenses

This project incorporates architectural patterns, bridge integrations, and runtime systems from the open source community:

| Project / Component | Upstream Source | License |
|---|---|---|
| **Dartotsu Extension Bridge** | [aayush2622/DartotsuExtensionBridge](https://github.com/aayush2622/DartotsuExtensionBridge) by [@aayush2622](https://github.com/aayush2622) (iOS OpenJDK Zero VM integration, TorrServer addon design, Tsundoku & iReader extensions architecture, repository formats) | UPL / GPL-3.0 |
| **Aniyomi** | [aniyomiorg/aniyomi](https://github.com/aniyomiorg/aniyomi) | Apache-2.0 |
| **CloudStream** | [recloudstream/cloudstream](https://github.com/recloudstream/cloudstream) | GPL-3.0 |
| **Kotatsu** | [KotatsuApp/Kotatsu](https://github.com/KotatsuApp/Kotatsu) | GPL-3.0 |
| **Tsundoku** | [tsundoku-otaku/tsundoku](https://github.com/tsundoku-otaku/tsundoku) | Apache-2.0 |
| **iReader** | [IReaderOrg/IReader](https://github.com/IReaderOrg/IReader) | Apache-2.0 |
| **LnReader** | [LNReader/lnreader](https://github.com/LNReader/lnreader) | Apache-2.0 |
| **Mangayomi** | [kodjodevf/mangayomi](https://github.com/kodjodevf/mangayomi) | Apache-2.0 |
| **TorrServer** | [YouROK/TorrServer](https://github.com/YouROK/TorrServer) & [ayman708-UX/torrserver_flutter](https://github.com/ayman708-UX/torrserver_flutter) | GPL-3.0 |
| **OpenJDK Zero iOS** | [1Selxo/Mangatan](https://github.com/1Selxo/Mangatan) & [kodjodevf/m_extension_server](https://github.com/kodjodevf/m_extension_server) | GPL-2.0-with-classpath-exception |

Special thanks to **[@aayush2622](https://github.com/aayush2622)** and the **Dartotsu** project for pioneering the embedded iOS JVM runtime architecture, TorrServerKit integration, and novel extension bridges.

---

*Maintained with ❤️ by [RyanYuuki](https://github.com/RyanYuuki).*
