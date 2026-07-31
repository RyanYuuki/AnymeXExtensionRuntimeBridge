// ============================================================================
// libtorrent_flutter — Example App
//
// A complete example demonstrating every major feature of the
// libtorrent_flutter package:
//
//   1. Engine initialisation with custom save path
//   2. Adding torrents via magnet links
//   3. Real-time download progress (speed, peers, ETA)
//   4. Pause / Resume / Remove torrents
//   5. File listing & selective file download (priority control)
//   6. HTTP streaming for video playback
//   7. Session configuration (speed limits, encryption, cache, etc.)
//
// For full API docs see: https://pub.dev/packages/libtorrent_flutter
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';

// ─── Entry Point ─────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise the libtorrent engine once, before runApp().
  //
  // • defaultSavePath — where downloaded files are written.
  // • fetchTrackers   — automatically fetches best public trackers for
  //                     better peer discovery on public magnets.
  // • pollInterval    — how often the engine emits status updates
  //                     (lower = more responsive UI, higher = less CPU).
  await LibtorrentFlutter.init(
    defaultSavePath:
        '${Directory.current.path}${Platform.pathSeparator}downloads',
    fetchTrackers: true,
    pollInterval: const Duration(milliseconds: 200),
  );

  runApp(const LibtorrentExampleApp());
}

// ─── App Shell ───────────────────────────────────────────────────────────────

class LibtorrentExampleApp extends StatelessWidget {
  const LibtorrentExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'libtorrent_flutter Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ─── Home Page ───────────────────────────────────────────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _magnetCtrl = TextEditingController();
  final _engine = LibtorrentFlutter.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('libtorrent_flutter Example'),
        actions: [
          // Show the native libtorrent version string.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                'libtorrent ${_engine.libraryVersion}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          // Settings button — opens the session config dialog.
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Session settings',
            onPressed: () => _showSettingsDialog(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Magnet input row ──────────────────────────────────────────
            _buildMagnetInput(),
            const SizedBox(height: 16),

            // ── Torrent list (live-updating) ──────────────────────────────
            Expanded(
              child: StreamBuilder<Map<int, TorrentInfo>>(
                stream: _engine.torrentUpdates,
                initialData: _engine.torrents,
                builder: (context, snap) {
                  final torrents = snap.data ?? {};
                  if (torrents.isEmpty) {
                    return const Center(
                      child: Text(
                        'Paste a magnet link above and tap Download to begin.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: torrents.length,
                    itemBuilder: (context, i) {
                      final t = torrents.values.elementAt(i);
                      return _TorrentCard(torrent: t, engine: _engine);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Magnet link input + Download button ─────────────────────────────────

  Widget _buildMagnetInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _magnetCtrl,
            decoration: const InputDecoration(
              hintText: 'Paste magnet link here…',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _addTorrent(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _addTorrent,
          icon: const Icon(Icons.download),
          label: const Text('Download'),
        ),
      ],
    );
  }

  void _addTorrent() {
    final magnet = _magnetCtrl.text.trim();
    if (magnet.isEmpty) return;

    // addMagnet() returns the torrent ID immediately.
    // The engine will resolve metadata in the background — the UI updates
    // automatically through the torrentUpdates stream.
    _engine.addMagnet(magnet);
    _magnetCtrl.clear();
  }

  // ── Session Settings Dialog ─────────────────────────────────────────────

  void _showSettingsDialog(BuildContext context) {
    // Read current config from the engine.
    final config = _engine.getDefaultConfig();

    final dlLimitCtrl =
        TextEditingController(text: config.downloadRateLimit.toString());
    final ulLimitCtrl =
        TextEditingController(text: config.uploadRateLimit.toString());
    var forceEncrypt = config.forceEncrypt;
    var disableDht = config.disableDht;
    var connLimit = config.connectionsLimit.toDouble();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Session Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Download speed limit (KB/s, 0 = unlimited).
                    TextField(
                      controller: dlLimitCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Download limit (KB/s, 0 = unlimited)',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 8),

                    // Upload speed limit.
                    TextField(
                      controller: ulLimitCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Upload limit (KB/s, 0 = unlimited)',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 12),

                    // Force encryption toggle.
                    SwitchListTile(
                      title: const Text('Force encryption'),
                      subtitle:
                          const Text('Only connect to encrypted peers'),
                      value: forceEncrypt,
                      onChanged: (v) =>
                          setDialogState(() => forceEncrypt = v),
                    ),

                    // DHT toggle.
                    SwitchListTile(
                      title: const Text('Disable DHT'),
                      subtitle: const Text(
                          'Turn off distributed hash table discovery'),
                      value: disableDht,
                      onChanged: (v) =>
                          setDialogState(() => disableDht = v),
                    ),

                    // Per-torrent connections limit.
                    // Lower (5–25) often streams BETTER on high-seed swarms
                    // — fewer peers = less head-of-line blocking by slow ones.
                    // TorrServer's default is 25.
                    ListTile(
                      title: const Text('Connections per torrent'),
                      subtitle: Text('${connLimit.toInt()} '
                          '(low = better for high-seed streaming)'),
                    ),
                    Slider(
                      min: 5,
                      max: 200,
                      divisions: 39,
                      value: connLimit.clamp(5, 200),
                      label: connLimit.toInt().toString(),
                      onChanged: (v) =>
                          setDialogState(() => connLimit = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    // Apply the new config to the running session.
                    _engine.configureSession(config.copyWith(
                      downloadRateLimit:
                          int.tryParse(dlLimitCtrl.text) ?? 0,
                      uploadRateLimit:
                          int.tryParse(ulLimitCtrl.text) ?? 0,
                      forceEncrypt: forceEncrypt,
                      disableDht: disableDht,
                      connectionsLimit: connLimit.toInt(),
                    ));
                    Navigator.pop(ctx);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _magnetCtrl.dispose();
    super.dispose();
  }
}

// ─── Torrent Card ────────────────────────────────────────────────────────────
//
// Displays a single torrent with:
//   • Name (or "Fetching metadata…" while resolving)
//   • Progress bar, state label, percentage, size done/total
//   • Download / upload speed, peer count, ETA
//   • Pause / Resume / Remove controls
//   • "Files" button to open file-level priority selection
//   • "Stream" button when streamable video files are available
// ─────────────────────────────────────────────────────────────────────────────

class _TorrentCard extends StatelessWidget {
  const _TorrentCard({required this.torrent, required this.engine});

  final TorrentInfo torrent;
  final LibtorrentFlutter engine;

  @override
  Widget build(BuildContext context) {
    final t = torrent;
    final pct = (t.progress * 100).toStringAsFixed(1);
    final done = formatBytes(t.totalDone);
    final total = formatBytes(t.totalWanted);
    final eta = t.state.isDone ? 'Complete' : formatEta(t);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title row + action buttons ──────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.name.isEmpty ? 'Fetching metadata…' : t.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Pause / Resume
                if (t.isPaused)
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    tooltip: 'Resume',
                    onPressed: () => engine.resumeTorrent(t.id),
                  )
                else if (!t.state.isDone)
                  IconButton(
                    icon: const Icon(Icons.pause),
                    tooltip: 'Pause',
                    onPressed: () => engine.pauseTorrent(t.id),
                  ),

                // Remove (with file deletion)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove & delete files',
                  onPressed: () =>
                      engine.removeTorrent(t.id, deleteFiles: true),
                ),
              ],
            ),

            // ── Progress bar ────────────────────────────────────────────
            const SizedBox(height: 8),
            LinearProgressIndicator(value: t.progress),
            const SizedBox(height: 6),

            // ── Status text ─────────────────────────────────────────────
            Text(
              '${t.state.label}  ·  $pct%  ·  $done / $total',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              '↓ ${formatSpeed(t.downloadRate)}  ·  '
              '↑ ${formatSpeed(t.uploadRate)}  ·  '
              '${t.numPeers} peers  ·  '
              'Seeds: ${t.numSeeds}  ·  '
              'ETA: $eta',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            // ── Save path ───────────────────────────────────────────────
            if (t.savePath.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                t.savePath,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // ── Error message (if any) ──────────────────────────────────
            if (t.errorMsg.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Error: ${t.errorMsg}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.redAccent),
              ),
            ],

            // ── Action buttons row ──────────────────────────────────────
            if (t.hasMetadata) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  // View & select individual files
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Files'),
                    onPressed: () => _showFilesDialog(context, t.id),
                  ),
                  const SizedBox(width: 8),

                  // Start HTTP streaming (for video files)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text('Stream'),
                    onPressed: () => _startStreaming(context, t.id),
                  ),
                  const SizedBox(width: 8),

                  // Force-recheck integrity
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Recheck'),
                    onPressed: () => engine.recheckTorrent(t.id),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── File listing & priority dialog ──────────────────────────────────────

  void _showFilesDialog(BuildContext context, int torrentId) {
    // getFiles() returns all files inside the torrent with their
    // current name, path, size and whether they are streamable.
    final files = engine.getFiles(torrentId);
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No files found (metadata not ready?)')),
      );
      return;
    }

    // Track per-file priority: 0 = skip, 4 = normal (default), 7 = highest
    final priorities = List<int>.filled(files.length, 4);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('Files (${files.length})'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: files.length,
                  itemBuilder: (ctx, i) {
                    final f = files[i];
                    return CheckboxListTile(
                      value: priorities[i] > 0,
                      onChanged: (checked) {
                        setDialogState(() {
                          priorities[i] = checked == true ? 4 : 0;
                        });
                      },
                      title: Text(
                        f.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${formatBytes(f.size)}'
                        '${f.isStreamable ? '  ·  Streamable' : ''}',
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    // Apply the chosen priorities.
                    // Files with priority 0 will not be downloaded.
                    engine.setFilePriorities(torrentId, priorities);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Streaming ───────────────────────────────────────────────────────────

  void _startStreaming(BuildContext context, int torrentId) {
    try {
      // startStream() picks the largest streamable file by default
      // (fileIndex: -1). It spins up a local HTTP server and returns
      // a StreamInfo with a URL you can hand to any video player
      // (e.g. video_player, media_kit, vlc_player, etc.).
      final stream = engine.startStream(torrentId);
      _showStreamDialog(context, stream);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stream error: $e')),
      );
    }
  }

  void _showStreamDialog(BuildContext context, StreamInfo initialStream) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Streaming'),
          content: StreamBuilder<Map<int, StreamInfo>>(
            stream: engine.streamUpdates,
            initialData: engine.streams,
            builder: (ctx, snap) {
              final info = snap.data?[initialStream.id] ?? initialStream;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The HTTP URL for the stream — pass this to your
                  // video player widget.
                  SelectableText(
                    info.url,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('State: ${info.streamState.name}'),
                  Text('File size: ${formatBytes(info.fileSize)}'),
                  Text(
                      'Buffer: ${info.bufferPieces} / ${info.readaheadWindow} pieces'),
                  Text(
                      'Buffer time: ${info.bufferSeconds.toStringAsFixed(1)}s'),
                  Text('Active peers: ${info.activePeers}'),
                  Text('Speed: ${formatSpeed(info.downloadRate)}'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: info.bufferPct),
                  const SizedBox(height: 4),
                  Text(
                    info.isReady
                        ? 'Ready for playback'
                        : info.isBuffering
                            ? 'Buffering…'
                            : info.streamState.name,
                    style: TextStyle(
                      color: info.isReady ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            // Copy the stream URL to clipboard for use in an external player.
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy URL'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: initialStream.url));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Stream URL copied!')),
                );
              },
            ),
            FilledButton(
              onPressed: () {
                engine.stopStream(initialStream.id);
                Navigator.pop(ctx);
              },
              child: const Text('Stop Stream'),
            ),
          ],
        );
      },
    );
  }
}
