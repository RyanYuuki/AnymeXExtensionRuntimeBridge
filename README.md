# AnymeX Extension Runtime Bridge

A powerful Flutter plugin built around a **unified, runtime-agnostic API** for loading and executing **Aniyomi**, **CloudStream**, **Mangayomi**, and **Sora** extension sources through a single consistent interface.

---

## 🏗️ Architecture

The bridge allows your app to stay small while offloading heavy execution logic to a dedicated runtime.

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
│  AnymeXRuntimeBridge     (Runtime Host)     │
│  ├─ Android: Bridge APK                     │
│  └─ Desktop: JRE + Bridge JAR               │
└─────────────────────────────────────────────┘
```

> **IMPORTANT:** Aniyomi and CloudStream will NOT work without loading the Runtime Bridge first.
> Separation is intentional — it avoids bundling heavy native dependencies (like the JVM or JRE) directly into your app.

---

## 🚀 Setup & Initialization

### 1. Initialize the Bridge
Call this once at the start of your app. This sets up the directory structure and database name.

```dart
await AnymeXExtensionBridge.init(
  isarInstance: isar, 
  projectName: 'AnymeX', // Your project name (used for folder naming)
  getDirectory: MyDirectoryResolver,
);
```

### 2. Prepare the Runtime
You have two ways to handle the runtime bridge:

- **`checkAndInitialize()`**: Checks if the bridge/JRE is already downloaded and initializes it if found. Use this on every app start for persistence.
- **`setupRuntime({force: false})`**: Downloads and installs the bridge. Set `force: true` to trigger an update of the Bridge JAR.

```dart
// Auto-detect existing files
await AnymeXRuntimeBridge.checkAndInitialize();

// Or show a download UI if missing
if (!AnymeXRuntimeBridge.controller.isReady.value) {
  // Trigger installation/download
  await AnymeXRuntimeBridge.setupRuntime();
}

// After initialization, register the bridged managers
final extManager = Get.find<ExtensionManager>();
await extManager.onRuntimeBridgeInitialization();
```

---

## 📚 API Reference

### `AnymeXExtensionBridge`
| Method | Description |
|--------|-------------|
| `init(...)` | Initialize the bridge (DB, Project Name, Dirs) |
| `dispose()` | Clean up resources |
| `isar` | Access the internal Isar instance |
| `isarSchema` | Required schemas for your Isar initialization |

### `AnymeXRuntimeBridge`
| Method | Description |
|--------|-------------|
| `setupRuntime({force, customUrl})` | Downloads/Updates the bridge host |
| `checkAndInitialize()` | Auto-detects existing files on startup |
| `isLoaded()` | Returns true if the bridge is currently active |
| `controller` | GetX controller for progress/status tracking |

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
| `onRuntimeBridgeInitialization()` | Register Aniyomi+CloudStream after bridge is ready |

### `SourceMethods` (Unified Interface)
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

## 📦 Models & Mappings

### Core Models
| Model | Description |
|-------|-------------|
| `Source` | Represents an extension source (installed or available) |
| `DMedia` | Media item (anime / manga / novel) |
| `DEpisode` | Episode or chapter |
| `Pages` | Paginated result container |
| `Video` | Video stream info (URL, quality, etc.) |
| `PageUrl` | Manga page image URL |
| `SourcePreference` | Extension preference entry |

### Manager IDs
| `managerId` | Backend | Platforms |
|-------------|---------|-----------|
| `aniyomi` | Aniyomi extensions | Android, Win, Mac, Linux |
| `cloudstream` | CloudStream plugins | Android only |
| `mangayomi` | Mangayomi JS extensions | All |
| `sora` | Sora extensions | All |

---
*Made with ❤️ by RyanYuuki.*
