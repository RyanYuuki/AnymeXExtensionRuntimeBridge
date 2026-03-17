# AnymeX Extension Runtime Bridge

> Based on [DartotsuExtensionBridge](https://github.com/aayush262/DartotsuExtensionBridge)

A Flutter plugin built around a **unified, runtime-agnostic API** for loading and executing **Aniyomi**, **CloudStream**, **Mangayomi**, and **Sora** extension sources through a single consistent interface.

This was built specifically for **AnymeX**'s architecture and may not suit every use case. It differs enough from DartotsuExtensionBridge that it warranted its own project.
---

## Uhh so benefits??

### 🚀 ~10 MB Smaller
All heavy extension logic lives in a separately loaded **AnymeX Runtime Host APK**. That alone saves ~10 MB of app size.

### ⚡ Single Unified API Across All Backends
This uses a single ```ExtensionManager``` to manage all extensions of all managers at once.

```dart
final source = extManager.installedAnimeExtensions.first;

// Works identically for Aniyomi, CloudStream, Mangayomi, or Sora:
final results = await source.methods.search('Naruto', 1, []);
final detail  = await source.methods.getDetail(results.list.first);
final videos  = await source.methods.getVideoList(detail.episodes!.first);
```

### 🔌 Auto-Aggregated Multi-Backend Lists
All registered backends automatically merge into single reactive lists. No per-backend queries:
- `installedAnimeExtensions`
- `installedMangaExtensions`
- `installedNovelExtensions`

### 📦 Aniyomi & Sora Adapters Included
The Aniyomi and Sora bridge adapters are ported from DartotsuExtensionBridge and integrated into the unified manager.
---

## Platform Support

| Platform | Supported |
|----------|-----------|
| Android  | ✅ Full support (Aniyomi + CloudStream via Runtime Host APK) |
| iOS      | ⚠️ Mangayomi + Sora only |
| macOS    | ⚠️ Mangayomi + Sora only |
| Linux    | ⚠️ Mangayomi + Sora only |
| Windows  | ⚠️ Mangayomi + Sora only |

> **Note:** Aniyomi and CloudStream extensions require the **AnymeX Runtime Host APK** on Android.

---

## Understanding the Two Components

> [!IMPORTANT]
> This project has **two distinct parts** that serve completely different purposes. Understanding this is essential before using the bridge.

### `AnymeXExtensionBridge` — The Dart / Flutter Side

This is the **Flutter plugin** you add to your app. It handles:
- Managing all extension backends (Mangayomi, Sora, Aniyomi, CloudStream)
- Aggregating installed and available sources into reactive lists
- Providing the unified `SourceMethods` API for querying sources
- Persisting settings and source metadata via Isar

**Mangayomi and Sora work out of the box with just this.** No extra setup needed — they run entirely within the Dart/Flutter environment.

### `AnymeXRuntimeBridge` — The Android Runtime Host

This is a **separate APK** (the AnymeX Runtime Host) that must be loaded at runtime on Android. It hosts the native Android extension runtimes that are required for:

- **Aniyomi** extensions (APK-based, Android-native)
- **CloudStream** plugins (JVM-based, Android-native)

> [!CAUTION]
> **Aniyomi and CloudStream will NOT work without loading the AnymeX Runtime Host APK first.**
> You must call `AnymeXRuntimeBridge.loadRuntimeHost(path)` (or `loadRuntimeHostFromPicker()`) before
> attempting to access any Aniyomi or CloudStream sources. Calling extension methods before the
> Runtime Host is loaded will result in an error.

The separation is intentional — it keeps the Flutter package small and avoids bundling heavy Android-native dependencies directly. The Runtime Host APK is distributed and loaded separately.

```
┌─────────────────────────────────────────────┐
│         Your Flutter App                    │
│                                             │
│  AnymeXExtensionBridge   (Dart plugin)      │
│  ├─ Mangayomi  ──────────► works natively   │
│  ├─ Sora       ──────────► works natively   │
│  ├─ Aniyomi    ──► needs AnymeXRuntimeBridge│
│  └─ CloudStream──► needs AnymeXRuntimeBridge│
│                                             │
│  AnymeXRuntimeBridge     (Runtime Host APK) │
│  └─ Loaded at runtime via loadRuntimeHost() │
└─────────────────────────────────────────────┘
```

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  anymex_extension_runtime_bridge:
    git:
      url: https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge.git
      ref: main
```

Then run:

```bash
flutter pub get
```

---

## Setup

### 1. Initialize the bridge

Call `AnymeXExtensionBridge.init()` early in your app startup (before using any extension APIs):

```dart
import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';

await AnymeXExtensionBridge.init(
  getDirectory: AnymeXExtensionBridge.defaultGetDirectory(),
);
```

You can also pass a custom `Isar` instance and HTTP client:

```dart
await AnymeXExtensionBridge.init(
  getDirectory: AnymeXExtensionBridge.defaultGetDirectory(
    baseDirectory: myAppDir,
    appFolderName: 'anymex',
  ),
  isarInstance: myIsar, // optional, auto-created if null
  http: myHttpClient,   // optional
);
```

### 2. Load the Runtime Host (Android only)

To use Aniyomi and CloudStream extensions, load the **AnymeX Runtime Host APK**:

```dart
// Let the user pick the APK from their device:
await AnymeXRuntimeBridge.loadRuntimeHostFromPicker();

// Or load from a known path:
await AnymeXRuntimeBridge.loadRuntimeHost('/path/to/runtimehost.apk');

// Check if loaded:
final loaded = await AnymeXRuntimeBridge.isLoaded();
```

After loading, call `onRuntimeBridgeInitialization()` on the `ExtensionManager` to register Aniyomi and CloudStream backends:

```dart
final extManager = Get.find<ExtensionManager>();
await extManager.onRuntimeBridgeInitialization();
```

---

## Usage

### Access the Extension Manager

```dart
import 'package:get/get.dart';
import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';

final extManager = Get.find<ExtensionManager>();
```

### Browse installed extensions

```dart
// Reactive lists — use in GetX widgets or observe via ever()
final animeExts  = extManager.installedAnimeExtensions;
final mangaExts  = extManager.installedMangaExtensions;
final novelExts  = extManager.installedNovelExtensions;
```

### Fetch available extensions from repos

```dart
// Add a repository
await extManager.addRepo(
  'https://raw.githubusercontent.com/your/repo/index.min.json',
  ItemType.anime,
  'mangayomi', // managerId: 'aniyomi', 'mangayomi', 'cloudstream', 'sora'
);

// Refresh
await extManager.refreshExtensions(refreshAvailableSource: true);

final available = extManager.availableAnimeExtensions;
```

### Install / Uninstall / Update

```dart
final source = extManager.availableAnimeExtensions.first;

await source.install();
await source.update();
await source.uninstall();
```

### Call source methods (unified API)

Every installed `Source` exposes the same `.methods` interface regardless of backend:

```dart
final source = extManager.installedAnimeExtensions.first;
final methods = source.methods;

// Listing
final popular = await methods.getPopular(1);
final latest  = await methods.getLatestUpdates(1);
final results = await methods.search('One Piece', 1, []);

// Detail
final detail = await methods.getDetail(results.list.first);

// Video (anime)
final videos = await methods.getVideoList(detail.episodes!.first);

// Streamed video (CloudStream)
final stream = methods.getVideoListStream(detail.episodes!.first);
await for (final video in stream!) {
  print(video.url);
}

// Pages (manga)
final pages = await methods.getPageList(detail.episodes!.first);

// Novel content
final content = await methods.getNovelContent('Chapter 1', 'chapterId');

// Preferences
final prefs = await methods.getPreference();
await methods.setPreference(prefs.first, 'new_value');
```

### Repo management

```dart
// Get all repos for a type
final repos = extManager.getAllRepos(ItemType.anime);

// Remove a repo
await extManager.removeRepo(repos.first, ItemType.anime);
```

---

## API Reference

### `AnymeXExtensionBridge`

| Method | Description |
|--------|-------------|
| `init(...)` | Initialize the bridge (call once at startup) |
| `defaultGetDirectory(...)` | Built-in directory resolver using `path_provider` |
| `dispose()` | Clean up resources |
| `isar` | Access the internal Isar instance |

### `AnymeXRuntimeBridge`

| Method | Description |
|--------|-------------|
| `loadRuntimeHost(path)` | Load the Runtime Host APK from a file path |
| `loadRuntimeHostFromPicker()` | Let user pick the APK via file picker |
| `isLoaded()` | Check if the Runtime Host is loaded |

### `ExtensionManager`

| Property / Method | Description |
|-------------------|-------------|
| `installedAnimeExtensions` | Reactive list of all installed anime sources |
| `installedMangaExtensions` | Reactive list of all installed manga sources |
| `installedNovelExtensions` | Reactive list of all installed novel sources |
| `availableAnimeExtensions` | Reactive list of all available anime sources |
| `availableMangaExtensions` | Reactive list of all available manga sources |
| `availableNovelExtensions` | Reactive list of all available novel sources |
| `addRepo(url, type, managerId)` | Add a repository to a specific backend |
| `removeRepo(repo, type)` | Remove a repository |
| `getAllRepos(type)` | Get all repos across all backends |
| `refreshExtensions(...)` | Re-fetch installed and/or available extensions |
| `updateAll()` | Update all sources that have an update available |
| `onRuntimeBridgeInitialization(...)` | Register Aniyomi+CloudStream after APK is loaded |

### `SourceMethods` (unified interface)

| Method | Description |
|--------|-------------|
| `getPopular(page)` | Fetch popular items |
| `getLatestUpdates(page)` | Fetch latest updates |
| `search(query, page, filters)` | Search for content |
| `getDetail(media)` | Fetch full detail of an item |
| `getVideoList(episode)` | Fetch video list for an episode |
| `getVideoListStream(episode)` | Stream video results one-by-one |
| `getPageList(episode)` | Fetch page list (manga) |
| `getNovelContent(title, id)` | Fetch novel chapter content |
| `getPreference()` | Get extension preferences |
| `setPreference(pref, value)` | Save extension preference |

---

## Models

| Model | Description |
|-------|-------------|
| `Source` | Represents an extension source (installed or available) |
| `DMedia` | Media item (anime / manga / novel) |
| `DEpisode` | Episode or chapter |
| `Pages` | Paginated result of `DMedia` items |
| `Video` | Video stream info |
| `PageUrl` | Manga page image URL |
| `SourcePreference` | Extension preference entry |

---

## Extension ID / Manager Mapping

| `managerId` | Backend |
|-------------|---------|
| `aniyomi` | Aniyomi APK extensions (Android only) |
| `cloudstream` | CloudStream plugins (Android only) |
| `mangayomi` | Mangayomi JS extensions (all platforms) |
| `sora` | Sora extensions (all platforms) |

---

## License

See [LICENSE](LICENSE).
