# Changelog

## 1.8.5

- Metadata-only release to improve pub.dev score (no code changes).

## 1.8.4

- **Live tuning: `configureSession` now propagates to active streams.**
  Previously, changing `connectionsLimit` (or other cache settings) via
  `configureSession()` only stored the new config and updated session-wide
  defaults — already-running streams kept their old per-torrent caps until
  restarted. The bridge now iterates active streams under the streams lock
  and re-applies `cache_size`, `reader_read_ahead`, and
  `torrent_handle::set_max_connections(connectionsLimit)` immediately. Move
  a slider, get instant peer-count changes mid-playback.

## 1.8.3

- **Fix: per-torrent `connections_limit` was a dead field.** `BtConfig.connectionsLimit`
  (default 25, TorrServer convention) was only stored in the cache struct
  and never passed to libtorrent — every torrent inherited the session-wide
  cap (500), so high-seed torrents would open 200+ connections and suffer
  head-of-line blocking that made them stream *worse* than low-seed ones.
  `lt_start_stream` and `lt_set_cache_settings` now call
  `torrent_handle::set_max_connections(connections_limit)` so the cap
  actually takes effect. Session-wide default lowered from 500 → 200.
  Example app gains a live "Connections per torrent" slider (5–200).

## 1.8.2

- **Streaming: disk-read prefetch.** `serve_range` now kicks off
  libtorrent disk reads for the next 1-2 pieces *before* blocking on
  the socket send of the current piece. By the time the current send
  finishes and the loop advances, the `read_piece_alert` for piece p+1
  is already sitting in the results map, so the next
  `read_piece_data()` call returns instantly instead of blocking ~5-15 ms
  on a disk round trip. Free socket-I/O ↔ disk-I/O overlap — noticeable
  on slow HDDs, large pieces, and whenever the player drains the
  pipeline faster than one piece per RTT.

## 1.8.1

- **Linux: fully self-contained binary.** OpenSSL is now statically linked
  into `liblibtorrent_flutter.so` instead of being loaded from the user's
  system at runtime. Previously consumers needed `libssl3` / `libcrypto3`
  installed (failing on minimal containers and older distros). Now the
  only runtime deps are libc / libstdc++ / libpthread, which every glibc
  system ships. CI verifies this via an `ldd` post-link check that fails
  the build if libssl/libcrypto leak into NEEDED. Matches the existing
  fully-static behaviour of macOS / Windows / iOS / Android.
- **Engine: ultimate streaming tweaks** for higher throughput on
  mid-swarm torrents:
  - `predictive_piece_announce = 500ms`: announce pieces before they
    finish hashing so peers start requesting from us earlier; raises
    reciprocity score → better unchoke priority on the next round.
  - `allowed_enc_level = pe_both`: explicitly negotiate full-stream RC4
    (MSE) when the peer supports it instead of header-only — bypasses
    more ISP DPI throttling on plain BitTorrent.
  - `prefer_udp_trackers = true`: try UDP trackers before HTTP for the
    same hostname (~10× faster scrape responses, better cold-start).
  - **Fallback public trackers**: when an `addMagnet()` URI ships with
    zero trackers (just an info-hash), the bridge now seeds a curated
    set of 8 reliable open UDP trackers so peer discovery doesn't have
    to wait for DHT bootstrap (which can take 30-60s cold).

## 1.8.0

- **Coverage**: Three new desktop architecture slices, prebuilt by CI:
  - **macOS**: the bundled dylib is now a real `universal2` (`arm64 + x86_64`).
    Previously the `prebuilt/macos/universal/liblibtorrent_flutter.dylib`
    file was misnamed — it was an arm64-only dylib that would silently fail
    to load on Intel Macs. Cross-compiled on a single `macos-14` runner
    (GitHub no longer offers Intel macOS runners) by building OpenSSL +
    libtorrent + the bridge twice (once per arch) and `lipo -create`-ing the
    two slices into a fat dylib. `MACOSX_DEPLOYMENT_TARGET` is `10.14`.
  - **Linux arm64**: covers Raspberry Pi 4/5, AWS Graviton, Asahi Linux, and
    every other ARM64 Linux box. CI now matrix-builds `linux-native-lib-x64`
    and `linux-native-lib-arm64` on GitHub's free `ubuntu-22.04-arm` native
    runner. The Linux CMakeLists picks the slice via
    `CMAKE_HOST_SYSTEM_PROCESSOR` (`aarch64` → arm64).
  - **Windows arm64**: covers Snapdragon X laptops and Surface Pro X.
    Cross-compiled from the `windows-2022` runner via vcpkg's
    `arm64-windows-static` triplet and `cmake -A ARM64`. The Windows
    CMakeLists picks the slice via `CMAKE_GENERATOR_PLATFORM` /
    `PROCESSOR_ARCHITECTURE`.
- **Release-asset names** changed accordingly:
  - `linux-native-lib.zip` → `linux-native-lib-x64.zip` + `linux-native-lib-arm64.zip`
  - `windows-native-lib.zip` → `windows-native-lib-x64.zip` + `windows-native-lib-arm64.zip`
  - `macos-native-lib.zip` is unchanged (single universal2 dylib inside)
  - All Android (`android-native-lib-<abi>.zip`) and iOS (`ios-native-lib.zip`)
    asset names are unchanged.
- **Removed `prebuilt/macos/universal/` arm64-only dylib** from the repo so
  that the next build pulls the real universal2 instead of falling back to
  an Intel-incompatible cached file.

## 1.7.10

- **Packaging**: The pub.dev tarball no longer ships ~200 MB of prebuilt
  native binaries (it was well over the 100 MB limit). On first build, each
  platform's build script downloads the matching binary from the GitHub
  Release for the resolved package version:
  - **Android** (`android/build.gradle`): downloads `android-native-lib-<abi>.zip`
    for `arm64-v8a`, `armeabi-v7a`, and `x86_64` into `prebuilt/android/<abi>/`.
    Pass `-PlibtorrentFlutterAbis=arm64-v8a` to limit which ABIs are fetched,
    or `-PlibtorrentFlutterSkipDownload=true` to opt out entirely.
  - **Windows** (`windows/CMakeLists.txt`): downloads `windows-native-lib.zip`
    into `prebuilt/windows/x64/`. Set `-DLIBTORRENT_FLUTTER_SKIP_DOWNLOAD=ON`
    to opt out.
  - **Linux** (`linux/CMakeLists.txt`): downloads `linux-native-lib.zip`
    into `prebuilt/linux/x64/`. Same `-DLIBTORRENT_FLUTTER_SKIP_DOWNLOAD=ON`
    opt-out.
  - **macOS** (`macos/libtorrent_flutter.podspec`): downloads
    `macos-native-lib.zip` and places `liblibtorrent_flutter.dylib` next to
    the podspec. Export `LIBTORRENT_FLUTTER_SKIP_DOWNLOAD=1` to opt out.
  - **iOS** (`ios/libtorrent_flutter.podspec`): downloads `ios-native-lib.zip`
    and extracts the XCFramework next to the podspec. Same
    `LIBTORRENT_FLUTTER_SKIP_DOWNLOAD=1` opt-out.

  Each script falls back to building from source if the download fails (or
  when `-DLIBTORRENT_FLUTTER_SKIP_DOWNLOAD` / the env var is set), so
  air-gapped builds still work — just drop the binaries into `prebuilt/`
  yourself, or rely on the source CMake/Gradle paths.

## 1.7.9

- **iOS encryption** (parity with Android 1.7.6+): The iOS XCFramework is now built with libtorrent's MSE/PE protocol encryption fully enabled. Previously the iOS slices shipped with `-Dencryption=OFF` and `-DTORRENT_USE_SSL=0`, which made `pe_settings.in_enc_policy` / `out_enc_policy` silently no-op. Many seedboxes refuse plaintext connections, so the effective swarm size on iOS was a fraction of what Android saw. With encryption on, iOS connects to the same set of peers Android does — expect noticeably faster initial buffering and more sustained playback bandwidth on tight swarms.
- **iOS build pipeline**: Cross-compile OpenSSL 3.2.1 statically for all three slices (`ios64-xcrun` device arm64, `iossimulator-xcrun` arm64 + x86_64), pass `-DOPENSSL_ROOT_DIR` + `-Dencryption=ON` to the libtorrent CMake, drop `-DTORRENT_USE_SSL=0` from the bridge compile so libtorrent's installed `config.hpp` (with `TORRENT_USE_OPENSSL`/`TORRENT_USE_LIBCRYPTO` auto-defined) matches what the bridge sees — prevents the silent ABI mismatch that was wiping out the encryption settings.
- **iOS optimization**: Bridge bumped from `-O2` to `-O3 -flto` on all three slices — same treatment Android got in 1.7.6. Faster piece-hash verification + tighter alert dispatch loops.
- **iOS static link**: OpenSSL `libssl.a` + `libcrypto.a` are extracted and merged into the final `liblibtorrent_flutter.a` for each slice, so apps still ship a single static library and there are no extra link-flag changes for downstream Flutter apps.
- **App Store note**: BitTorrent's Message Stream Encryption falls under US EAR §740.17(b)(1) ("standard cryptography for interoperability"), so it qualifies for the export-compliance exemption. Apps using this plugin can declare `ITSAppUsesNonExemptEncryption = false` in their `Info.plist` and skip annual self-classification reports.
- **Streaming**: Widened `serve_range` priority pipeline from current+2 to current+16 pieces with an 80 ms deadline gradient — keeps peer request queues full so the swarm doesn't idle between piece completions. The deadline picker still orders by deadline so the immediate piece keeps top focus, the extra entries just prevent pipeline starvation.
- **Seeking**: Rewrote the HTTP seek-detection path to be minimal — `clear_piece_deadlines()` + a single `set_piece_deadline(seek_piece, 0)`, then let `serve_range` apply its normal 16-piece gradient on the first iteration. Removes ~1.2 s of artificial seek latency that came from the old 4-piece, 300 ms-stagger setup, and eliminates the picker double-rebuild that happened when seek-path priorities fought `serve_range`'s priorities.
- **Settings**: `request_queue_time` 3 → 1 second — in-flight peer pipeline drains 3× faster on priority changes, making seek response correspondingly faster.
- **Settings**: `whole_pieces_threshold` 20 → 0 — block requests within a piece now parallelize across multiple peers instead of being served by a single peer. Largest single seek-latency win on well-populated swarms.
- **Settings**: `piece_extent_affinity` false → true — keeps a peer downloading the same file region instead of jumping around, reducing piece-completion variance (= less stutter during sustained playback).
- **Settings**: `strict_end_game_mode` true → false — enables block-level duplication on the trailing edge of in-progress pieces. With strict mode + a small critical window, end-game never triggered and peers sat waiting on a single slow block; non-strict mode duplicates the last blocks across peers so one slow peer can't hold up a piece.
- **Settings**: `max_queued_disk_bytes` 16 MB → 64 MB — absorbs burst writes when many peers deliver simultaneously right after a seek.

## 1.7.8

- **Revert**: Rolled back streaming engine changes from 1.7.6–1.7.7 (wider priority window, prefetch changes, notifySeek API, FIN detection) — reverted to the stable 1.7.4 streaming logic with the 1.7.5 `is_ephemeral` bug fix
- **Kept**: Android encryption build (OpenSSL 3.2.1, `-Dencryption=ON`, `-O3 -flto`) from 1.7.6

## 1.7.7

- **Seeking**: Added `notifySeek()` API — Dart can now notify the native engine of a seek directly, bypassing HTTP detection entirely. When using players like mpv that buffer heavily (~150 MB demuxer cache), seeks within the cached region never triggered a new HTTP range request, causing 25+ second delays. The engine now responds to seeks within milliseconds regardless of player cache state
- **Seeking**: Non-blocking FIN/RST detection in the HTTP send loop — uses `WSAPoll`/`poll` + `MSG_PEEK recv` between send iterations to detect when the player closes the connection, enabling faster seek recovery for out-of-cache seeks
- **Seeking**: On seek, all non-tail piece priorities are reset to `dont_download` — prevents old-position pieces from competing for bandwidth with the new seek target
- **Streaming**: Widened priority lookahead from current+2 to current+8 pieces with staggered priorities (first 3 at priority 6, rest at priority 4) and wider deadline spacing — keeps the download pipeline full while concentrating bandwidth on the immediate piece
- **Streaming**: Expanded disk prefetch from 3 to 5 pieces — more pieces are pre-read from storage while the current piece is being sent, reducing I/O stalls between pieces

## 1.7.6

- **Build (Android)**: Enabled encryption — libtorrent is now compiled with `-Dencryption=ON` and statically linked against OpenSSL 3.2.1 cross-compiled for each ABI. Peers can now negotiate encrypted connections (`pe_enabled`/`pe_forced`), dramatically improving peer availability and download speeds in swarms that prefer or require encryption
- **Build (Android)**: Cross-compiles OpenSSL 3.2.1 as static libraries (`libssl.a`, `libcrypto.a`) for `arm64-v8a`, `armeabi-v7a`, and `x86_64` — no runtime OpenSSL dependency on the device
- **Build (Android)**: Upgraded compiler optimization from `-O2` to `-O3` with link-time optimization (`-flto`) for faster piece hashing, alert processing, and streaming throughput
- **Build (Android)**: Removed `-DTORRENT_USE_SSL=0` from the bridge build — encryption settings in C++ (`pe_enabled`/`pe_forced`) are no longer silently ignored
- **Build (Android)**: Added `-fPIC` to OpenSSL cross-compilation for armeabi-v7a — fixes linker error with 32-bit ARM assembly relocations
- **Streaming**: Reduced memory copies per piece from 3 to 1 — `ReadResult` now uses `shared_ptr<vector<char>>` so piece data flows from alert to cache to socket without redundant copies
- **Streaming**: Widened priority lookahead from current+2 to current+5 pieces — more peers download ahead of playback, reducing stalls on unstable connections
- **Streaming**: Expanded disk prefetch from 1 to 3 pieces — next 3 downloaded pieces are pre-read from libtorrent storage while the current piece is being sent to the player
- **Streaming**: Increased socket send buffer from 2 MB to 8 MB — prevents kernel buffer stalls on fast networks

## 1.7.5

- **FIX**: Added `is_ephemeral` check around the `metadata_received_alert` handler so that only streaming torrents get paused/zeroed after metadata, not regular downloads

## 1.7.4

- **Streaming**: Removed `sequential_download` mode — piece order is now driven entirely by `set_piece_deadline`, libtorrent's purpose-built time-critical mechanism. Improves seek recovery and swarm efficiency
- **Streaming**: Added hot piece cache — `on_piece_read` populates `CachePiece` buffers in memory, `read_piece_data` checks cache first. Instant re-reads for player probes, overlapping range requests, and small backward seeks
- **Streaming**: Trailing retention window — last 3 played pieces are kept alive instead of being immediately set to `dont_download`. Handles player re-reads and small rewinds without re-downloading
- **Streaming**: Adaptive bitrate estimation — startup piece count and buffer reporting now scale with file size. A 1.2 GB file gets ~2 critical startup pieces; a 4 GB file gets 1–2 instead of the old fixed 5, dramatically reducing time-to-first-frame for large files
- **Streaming**: Tail (moov atom) priority lowered from `top_priority` to priority 5 with 1000 ms deadlines — head startup pieces (priority 7, deadline 0–100 ms) always win the time-critical picker, preventing tail downloads from stealing bandwidth at startup
- **Seeking**: Trailing retention window is flushed on seek — old played pieces are dropped to `dont_download` immediately, freeing all bandwidth for the new seek position

## 1.7.3

- **FIX (CRASH)**: Fixed `SIGABRT` crash on stream shutdown — `cache->close()` destroyed `TorrReader` objects and their mutexes while HTTP client threads were still using them. Reordered shutdown to join all threads before closing the cache
- **FIX**: Added guard in `close_reader()` to skip cleanup if the cache is already closed, preventing double-free of reader mutexes
- **FIX**: `read_piece_data()` now checks `active` flag in its wait predicate — threads wake immediately on shutdown instead of blocking for up to 10 seconds
- **FIX**: `lt_destroy_session` no longer holds `streams_mu` while joining threads, preventing deadlock with the alert thread
- **HARDENING**: All thread entry points (`handle_connection`, client thread lambda), shutdown paths (`lt_stop_stream`, `lt_destroy_session`), and cache cleanup (`close_reader`, `TorrCache::close`) wrapped in try-catch — the native library will never crash the app, even on unexpected shutdown races

## 1.7.2

- **FIX (CRASH)**: Fixed `SIGABRT` crash (`pthread_mutex_destroy called on a destroyed mutex`) when stopping a stream — HTTP client handler threads were detached and continued accessing `StreamEngine` mutexes after the engine was destroyed. Client threads are now tracked, joined, and their sockets force-closed during shutdown
- **FIX**: Fixed potential double-close of the HTTP listen socket during stream shutdown
- **FIX**: `lt_destroy_session` now properly closes listen sockets and joins client threads before destroying stream engines

## 1.7.1

- **Streaming**: Replaced TorrServer-style async cache pipeline with lt2http-style direct storage reads — pieces are read straight from libtorrent disk storage instead of going through an intermediate RAM cache, eliminating seek delays
- **Streaming**: Narrowed priority window from 25-piece gradient (Now/Next/Readahead/High/Normal) to just current piece + 2 ahead — focuses 100% of bandwidth on what the player actually needs
- **Streaming**: 100% forward cache — everything ahead of playback, nothing behind. A 64 MB cache can now stream a 60 GB file by aggressively evicting played pieces
- **FIX**: Fixed downloads being killed during gaps between player HTTP requests — `clear_priority_impl()` was setting ALL pieces to `dont_download` when no readers existed
- **FIX**: Protected current reader piece and next piece from cache eviction, preventing evict-download-evict loops at piece boundaries
- **FIX**: Removed detached threads that spawned `clean_pieces()` and `get_removable_pieces()` on every piece write/read — these overrode `serve_range` priorities and stopped downloads
- **Build (Windows)**: Reduced DLL size from 9.4 MB to 146 KB

## 1.7.0

- **FIX (macOS)**: Fixed crash on launch — `libssl.3.dylib` / `libcrypto.3.dylib` were referenced via hardcoded Homebrew paths (`/opt/homebrew/opt/openssl@3/lib/...`), which don't exist on end-user machines. The dylib now uses `@loader_path/` references and bundles OpenSSL alongside the plugin
- **Build (macOS)**: Added `install_name_tool` POST_BUILD step in CMakeLists.txt to automatically rewrite OpenSSL load paths during compilation
- **Build (macOS)**: Added `build_macos.sh` — one-command script that builds the dylib, copies OpenSSL from Homebrew, fixes all dylib cross-references, and places files in `macos/` and `prebuilt/macos/universal/`
- **Packaging (macOS)**: Updated podspec to vendor `libssl.3.dylib` and `libcrypto.3.dylib` alongside the main plugin dylib
- **Streaming**: Improved seek performance — 5 deadline pieces at deadline=0, unlimited unchoke slots, optimized `cancel_non_critical()` timing
- **Engine**: `unchoke_slots_limit` changed from 4 to unlimited (-1) — fixes issue where only 4 peers would upload despite hundreds connected

## 1.6.9

- **Engine**: Complete rewrite of the C++ streaming engine — new priority system, HTTP server, and piece management
- **Streaming**: 5-level priority gradient (NOW=7, NEXT=6, READAHEAD=5, BACK=1, SKIP=0) — only downloads the playback window and head/tail metadata, not the entire file
- **Streaming**: `set_piece_deadline()` for time-critical downloads — pieces requested from multiple peers simultaneously, slow requests auto-cancelled
- **Streaming**: Adaptive readahead window (3–50 pieces) grows with smooth playback, resets on seek
- **Streaming**: 8-piece backward buffer keeps recently-played pieces available for quick rewinds
- **Streaming**: Configurable RAM piece cache via `maxCacheBytes` — from 128MB for smart TVs to 2GB for desktops. Sliding window eviction with safe-zone protection around the playhead
- **Seeking**: Threaded HTTP connection handler — new connections preempt old ones instantly via socket close, no more blocking the accept loop
- **Seeking**: `clear_piece_deadlines()` on seek — immediately stops downloading for old position and redirects bandwidth to new target
- **Seeking**: Aggressive seek deadlines (6 pieces at 200ms spacing) at the new position
- **Seeking**: `seek_generation` counter aborts blocked piece waits within milliseconds
- **Performance**: Condition-variable-based piece waiting — zero CPU polling
- **Performance**: Alert-driven piece tracking via `piece_finished_alert` — no status polling for piece availability
- **Performance**: Piece data cache with safe-zone (5 pieces around playhead never evicted), smart trim on seek preserves nearby cached data
- **Tuning**: `max_failcount=3` — peers survive seek transitions instead of being dropped
- **Tuning**: `peer_turnover` 5% every 30s — faster replacement of slow peers
- **Tuning**: Connection flood on startup (`connection_speed=200`, `torrent_connect_boost=200`) for fast peer acquisition
- **API**: `startStream()` now accepts `maxCacheBytes` to control RAM usage (0 = default ~128MB)
- **API**: Backward-compatible `bufferPct` getter on `StreamInfo`
- **API**: New `StreamState` enum (idle, buffering, ready, seeking, error) and `streamState` field on `StreamInfo`
- **API**: New fields on `StreamInfo`: `bufferSeconds`, `bufferPieces`, `readaheadWindow`, `activePeers`, `downloadRate`
- **Compat**: All existing API methods preserved — `addMagnet()`, `startStream()`, `stopStream()`, `disposeTorrent()`, etc. work unchanged

## 1.6.8

- **iOS**: Built XCFramework with both device (arm64-iphoneos) and simulator (arm64+x86_64-iphonesimulator) slices — iOS Simulator now works on Apple Silicon and Intel Macs
- **iOS**: Replaced fat `.a` binary with `.xcframework` — Apple's recommended approach for multi-platform static libraries
- **iOS**: Updated podspec to use `vendored_frameworks` with SDK-conditional `-force_load` linker flags
- **CI**: Build workflow now compiles libtorrent + torrent_bridge for three iOS targets (arm64 device, arm64 simulator, x86_64 simulator) and packages them via `xcodebuild -create-xcframework`
- **Publish**: Dropped Android x86_64 prebuilt from pub package to stay under 100 MB limit



## 1.6.6

IOS fixes

## 1.6.6

- **FIX (iOS)**: Added `SystemConfiguration` framework dependency to podspec — resolves `Undefined symbol: _SCNetworkReachabilityCreateWithAddress` linker errors when building for iOS release

## 1.6.5

- **CRITICAL FIX**: Concurrent connections (head + tail) were killing each other — every new HTTP connection overwrote a global request ID, instantly aborting the other. Players that open two connections (VLC, mpv, ExoPlayer) would loop endlessly until enough pieces were cached. Replaced with a seek-generation counter that only aborts stale connections on actual seeks
- **FIX**: Tail/metadata range requests no longer hijack `read_head` — the priority loop stays focused on the playback position instead of jumping to the end of the file
- **Streaming**: LRU piece cache (48 entries) — avoids repeated disk reads for recently served pieces
- **Streaming**: Head + tail preload on stream start — first 5 pieces get staggered deadlines, last ~512KB is pre-fetched for container metadata (MKV cues, MP4 moov)
- **Streaming**: Dynamic readahead window (8–40 pieces) scales with download speed, targeting ~15s of buffer
- **Streaming**: Wider inline lookahead (6 pieces) with staggered deadlines during serve
- **Seeking**: Cache invalidation on seek — evicts stale pieces, preserves tail pieces
- **Seeking**: Wider post-seek focus (5 queued pieces instead of 2)
- **Engine**: Fixed `suggest_mode` — was set as bool instead of the correct enum value
- **Engine**: Fixed `torrent_connect_boost` exceeding documented max (255)
- **Engine**: `mixed_mode_algorithm` set to `peer_proportional` — stops starving uTP peers behind NAT
- **Engine**: Added DHT bootstrap nodes, `piece_extent_affinity`, `auto_sequential`
- **Engine**: Tuned send buffer watermarks, peer turnover, socket buffer sizes
- **Serve**: DLNA headers for smart TV compatibility
- **Serve**: CORS OPTIONS preflight support
- **Serve**: 2MB send buffer, 1MB send chunks
- **Serve**: Case-insensitive HTTP Range header parsing
- **Serve**: Adaptive priority loop interval (100ms buffering, 250ms steady)

## 1.6.4

- **CRITICAL FIX**: HTTP server sent `Connection: keep-alive` but closed the socket after every request — VLC trusted the keep-alive promise, tried to reuse the dead connection, got a broken pipe, and rendered a black screen. Fixed by switching to `Connection: close`, which correctly tells the player to open a new TCP connection for each range request. This is the standard model used by other torrent streaming servers.
- **Serve**: HEAD requests now return headers and close cleanly without falling through to the data-serving path
- **Serve**: Removed redundant `while` loop around single-use connection handling — the code now clearly reflects the one-request-per-connection model

## 1.6.3

- **Streaming**: Instant start — staggered piece deadlines (0ms, 500ms, 1000ms…) on startup instead of flat 0ms for all. libtorrent's time-critical picker now funnels all bandwidth to piece 0 first, so playback can begin as soon as 1 piece arrives instead of waiting for 8
- **Streaming**: Shrunk critical window from 6 pieces → 2, hot window from 9 → 5, readahead from 15 → 6 — concentrates bandwidth on the most urgent data per libtorrent's streaming docs: "any block you request that is not urgent takes away bandwidth from urgent pieces"
- **Streaming**: Buffer percentage now based on the 2-piece critical window — reports "ready" faster since it no longer waits for 6 pieces
- **Seeking**: Tighter seek focus — 2 pieces at staggered near-zero deadlines + 2 more at 200ms stagger (was 4 all at 0ms), reducing bandwidth dilution on seek
- **Seeking**: Seek cooldown reduced from 1000ms → 100ms — priority loop resumes almost immediately after a seek instead of staying blind for a full second
- **Seeking**: Wait timeout reduced from 120s → 30s — fails faster on dead peers instead of hanging
- **Performance**: Priority loop now runs every 100ms (was 200ms) for faster reaction to playback position changes
- **Performance**: libtorrent `tick_interval` set to 100ms (was 500ms default) — internal scheduler reacts 5x faster to deadline changes and priority updates
- **Serve**: Inline lookahead reduced from 5 → 3 pieces with 100ms stagger (was 10ms) — less bandwidth competition with the current piece

## 1.6.2

- **CRITICAL FIX**: Removed `force_recheck()` from cache eviction — it was re-hashing the ENTIRE torrent, marking ALL pieces (including currently streaming ones) as unknown, killing the stream
- **Streaming**: Capped readahead window to 50% of cache capacity — prevents downloading so far ahead that the cache overflows and evicts data at the current playback position
- **Streaming**: Hard safety floor — cache eviction NEVER evicts anything within 5 pieces of the current playhead, regardless of cache pressure

## 1.6.1

- **Streaming**: Fixed serial pipeline stall after seek — `serve_range` now pre-primes the next 5 pieces with priority 7 and staggered deadlines before each `wait_for_piece` call, so the swarm downloads them in parallel instead of one at a time
- **Streaming**: Reduced seek cooldown from 3s → 1s — the new serve_range lookahead covers the gap, so the priority loop can resume sooner and set broader readahead windows

## 1.6.0

- **Streaming**: Rewrote priority system using torrest-cpp's proven priority-only-upgrade pattern — never downgrade piece priorities, staggered `i*10ms` deadlines for the hot window
- **Streaming**: Increased critical window from 3 → 5 pieces at deadline=0ms for faster initial playback
- **Streaming**: Total seek focus — on seek, all piece priorities are wiped and ONLY the seek position + 3 pieces get deadline=0ms with a 3-second cooldown before the priority loop resumes
- **Streaming**: `wait_for_piece` timeout increased from 15s → 120s to prevent "Stream ends prematurely" errors during slow torrent startup
- **Streaming**: Reduced readahead buffer from 30 → 15 pieces to concentrate bandwidth closer to the playhead
- **Engine**: Added `no_recheck_incomplete_resume` — skips file recheck on resume for faster startup
- **Engine**: Added `allow_multiple_connections_per_ip` — connects to seedboxes, VPNs, and shared NAT peers
- **Engine**: Added `peer_connect_timeout=3s` for faster peer handshakes
- **Engine**: Tuned timeouts to stop peer churn (`piece_timeout` 2→5s, `request_timeout` 2→4s, `peer_timeout` 5→10s) — proven by libtorrent issue #7666, torrest, and Elementum
- **Engine**: `whole_pieces_threshold` increased 5 → 20, forcing fast peers to complete whole pieces instead of scattering blocks

## 1.5.0

- **Streaming**: Removed speculative tail preloading — the engine no longer downloads the last 4MB of a file at startup. Modern players (MPV, VLC, etc.) fetch container metadata (MP4 moov atom, MKV cues) on-demand via HTTP range requests, which the built-in server already supports
- **Streaming**: Head-only preload now sets 8 pieces at flat deadline=0ms instead of staggered 30ms intervals, focusing 100% of startup bandwidth on the beginning of the file
- **Streaming**: Removed file anchor logic from the priority loop that re-prioritized the last 2 pieces every 200ms, which competed with the playhead for bandwidth
- **Performance**: Startup time reduced from ~30–60s to ~5–15s by eliminating bandwidth competition between head and tail piece downloads

## 1.4.0

- **Platform**: Added iOS support

## 1.3.0

- **Platform**: Added iOS support (arm64 device + x86_64 simulator, universal static library)
- **CI**: New `build-ios` job cross-compiles libtorrent + torrent_bridge as a static `.a` for iOS, merged with `lipo`
- **Packaging**: iOS podspec with `-force_load` so all FFI symbols are visible via `DynamicLibrary.process()`

## 1.2.0

- **License**: Switched to GPL v3 (OSI-approved)
- **Streaming**: Dual-end preloading — fetches first 4MB and last 4MB of the file simultaneously on stream start. The tail contains the MP4/MKV moov atom (seek table), enabling instant seeking without buffering the whole file first
- **Streaming**: Staggered 30ms piece deadlines on the head (down from 45ms) for faster playback start
- **API**: `disposeTorrent(id)` — stop streams, remove torrent, and delete files in one call
- **API**: `disposeAll()` — clean up every torrent and stream at once (ideal for exit button)
- **API**: `startStream()` now accepts `maxCacheBytes` for a sliding window RAM cache limit
- **API**: `init()` now accepts `defaultSavePath` (defaults to system temp dir — no permission setup needed)
- **API**: `addMagnet()` and `addTorrentFile()` `savePath` is now optional (uses `defaultSavePath`)
- **README**: Fully rewritten with complete API documentation and code examples

## 1.1.0

- **Streaming**: Removed `sequential_download` flag (conflicts with `set_piece_deadline`)
- **Streaming**: Reduced readahead from 150 to 30 pieces to avoid excessive pre-buffering
- **Streaming**: `clear_piece_deadlines()` on seek + 1-second cooldown for faster seek response
- **Streaming**: Re-enabled uTP for incoming and outgoing connections (reaches more peers behind NAT)
- **Cache**: Configurable RAM cache limit with percentage-based sliding window eviction (10% safety buffer, min 5 pieces)
- **Save path**: Defaults to system temp directory on all platforms
- **CI**: Automatic GitHub Release creation with zipped native libraries on every build
- **pubspec**: Added `repository`, `issue_tracker`, and `topics` fields for pub.dev discoverability

## 1.0.0

- Initial release
- Native libtorrent 2.0 bindings via Dart FFI
- Built-in HTTP streaming server with byte-range support
- Windows, Linux, macOS, and Android support with prebuilt binaries (no build required)
- Auto-fetches best public trackers on startup
- Magnet link and .torrent file support
- Per-file streaming with automatic largest-file selection
- `torrentUpdates` and `streamUpdates` streams for reactive UI
- DHT, PEX, LSD peer discovery
