import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import '../../core/isbn.dart';
import '../../data/catalog_actions.dart';
import '../../data/models/book.dart';
import '../catalog/book_detail_screen.dart';
import '../catalog/book_edit_screen.dart';
import '../common/widgets.dart';
import 'ocr.dart';
import 'scan_result_sheet.dart';

enum _ScanAction { added, extraCopy, moved }

/// One scan in the current session. The row shows the book's live state
/// (so it updates when background lookups finish), and [before] lets Undo
/// reverse exactly what the scan did.
class _SessionEntry {
  _SessionEntry(this.bookId, this.isbn13, this.action, {this.before});
  final String bookId;
  final String isbn13;
  final _ScanAction action;

  /// The book before an extra copy or move, restored by Undo.
  final Book? before;
}

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, required this.active});

  /// Whether the Scan tab is visible; the camera only runs while it is.
  final bool active;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.ean13],
    detectionSpeed: DetectionSpeed.normal,
  );
  bool _busy = false;
  String? _lastIsbn;
  DateTime _lastAt = DateTime(2000);
  final List<_SessionEntry> _session = [];

  /// Full-screen colour flash: green = saved, amber = already in catalog.
  Color? _flash;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(_startCamera());
  }

  @override
  void didUpdateWidget(ScanScreen old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      unawaited(widget.active ? _startCamera() : _stopCamera());
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// Starts the camera if this tab is showing and nothing else is using it.
  /// Errors (already running, permission denied) are shown by the scanner
  /// widget's error view instead of crashing.
  Future<void> _startCamera() async {
    if (!mounted || !widget.active) return;
    try {
      await _controller.start();
    } catch (e) {
      debugPrint('Camera start failed: $e');
    }
  }

  Future<void> _stopCamera() async {
    try {
      await _controller.stop();
    } catch (e) {
      debugPrint('Camera stop failed: $e');
    }
  }

  /// Pauses the camera while [task] shows a dialog, sheet or other screen.
  Future<T> _withCameraPaused<T>(Future<T> Function() task) async {
    await _stopCamera();
    try {
      return await task();
    } finally {
      await _startCamera();
    }
  }

  void _flashScreen(Color color) {
    if (!mounted) return;
    _flashTimer?.cancel();
    setState(() => _flash = color);
    _flashTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _record(_SessionEntry entry) {
    if (mounted) setState(() => _session.insert(0, entry));
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || !isBooklandEan(raw)) continue;
      final isbn = normalizeIsbn(raw);
      final now = DateTime.now();
      // The same barcode stays in view for a while; ignore repeats.
      if (isbn == _lastIsbn && now.difference(_lastAt).inSeconds < 4) return;
      _lastIsbn = isbn;
      _lastAt = now;
      unawaited(_handleIsbn(isbn));
      return;
    }
  }

  Future<void> _handleIsbn(String isbn13) async {
    if (_busy) return;
    _busy = true;
    try {
      unawaited(HapticFeedback.mediumImpact());
      unawaited(SystemSound.play(SystemSoundType.click));
      final settings = ref.read(effectiveScanSettingsProvider);
      final books = ref.read(booksProvider).value ?? const <Book>[];
      final existing = findByIsbn(books, isbn13);
      if (existing != null) {
        await _handleDuplicate(existing, settings.locationId);
      } else if (settings.batchMode) {
        await _saveQuick(isbn13, settings);
      } else {
        final saved = await _withCameraPaused(
          () => showScanResultSheet(context, isbn13: isbn13),
        );
        if (saved != null) {
          _record(_SessionEntry(saved.id, isbn13, _ScanAction.added));
          _flashScreen(Colors.green);
        }
      }
    } finally {
      _busy = false;
    }
  }

  /// Quick scan: save at once (so a shelf never waits on the network); the
  /// app's background lookup fills in the details, online or later.
  Future<void> _saveQuick(String isbn13, ScanSettings settings) async {
    final book = ref
        .read(catalogActionsProvider)
        .newBookFromScan(
          isbn13,
          locationId: settings.locationId,
          tagIds: settings.tagIds,
        );
    await ref.read(catalogRepositoryProvider).saveBook(book);
    _record(_SessionEntry(book.id, isbn13, _ScanAction.added));
    _flashScreen(Colors.green);
  }

  Future<void> _handleDuplicate(Book existing, String? hereId) async {
    _flashScreen(Colors.amber);
    final locations = ref.read(locationMapProvider);
    final here = locations[hereId];
    final choice = await _withCameraPaused(
      () => showDialog<_ScanAction>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Already in the catalog'),
          content: Text(
            '"${existing.title}"\n'
            '${locationLabel(locations[existing.locationId])}'
            '${existing.copies > 1 ? ' · ${existing.copies} copies' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, _ScanAction.extraCopy),
              child: const Text('Add a copy'),
            ),
            if (existing.locationId != hereId)
              FilledButton(
                onPressed: () => Navigator.pop(context, _ScanAction.moved),
                child: Text('Move to ${here?.name ?? 'no location'}'),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await ref
        .read(catalogRepositoryProvider)
        .saveBook(
          choice == _ScanAction.extraCopy
              ? existing.copyWith(copies: existing.copies + 1)
              : CatalogActions.moveBook(existing, here, locations),
        );
    _record(
      _SessionEntry(existing.id, existing.isbn13!, choice, before: existing),
    );
  }

  Future<void> _undo(_SessionEntry entry) async {
    final repo = ref.read(catalogRepositoryProvider);
    if (entry.action == _ScanAction.added) {
      await repo.deleteBook(entry.bookId);
    } else if (entry.before != null) {
      await repo.saveBook(entry.before!);
    }
    if (mounted) setState(() => _session.remove(entry));
  }

  Future<void> _readPrintedIsbn() async {
    final isbn = await _withCameraPaused(() async {
      final OcrResult? result;
      try {
        result = await captureAndReadIsbn();
      } on PlatformException catch (e) {
        if (mounted) {
          showSnack(context, 'Camera unavailable: ${e.message ?? e.code}');
        }
        return null;
      }
      if (!mounted || result == null) return null;
      final found = result.isbns;
      final String? chosen;
      if (found.length == 1) {
        chosen = found.single;
      } else if (found.length > 1) {
        chosen = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Which ISBN?'),
            children: [
              for (final i in found)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, i),
                  child: Text(displayIsbn(i)),
                ),
            ],
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('No ISBN found'),
            content: const Text(
              'Try again closer to the ISBN, with good light and the text '
              'level. It is usually on the back cover or the copyright page.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return null;
      }
      if (chosen == null || !mounted) return null;
      final ok = await confirm(
        context,
        title: 'Use this ISBN?',
        message: displayIsbn(chosen),
        action: 'Look up',
      );
      return ok ? chosen : null;
    });
    if (isbn != null) await _handleIsbn(isbn);
  }

  Future<void> _typeIsbn() async {
    final text = await showTextDialog(
      context,
      title: 'Type ISBN',
      hint: 'ISBN-10 or ISBN-13',
      action: 'Look up',
    );
    if (text == null || text.isEmpty || !mounted) return;
    final isbn = toIsbn13(text);
    if (isbn == null) {
      showSnack(context, 'That is not a valid ISBN — check the digits.');
      return;
    }
    await _handleIsbn(isbn);
  }

  Future<void> _noIsbn() async {
    final settings = ref.read(effectiveScanSettingsProvider);
    await _withCameraPaused(
      () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookEditScreen(
            initialLocationId: settings.locationId,
            initialTagIds: settings.tagIds,
          ),
        ),
      ),
    );
  }

  Widget _sessionTile(_SessionEntry e, Map<String, Book> books) {
    final book = books[e.bookId];
    final String title;
    final String subtitle;
    if (book == null) {
      title = 'Removed';
      subtitle = displayIsbn(e.isbn13);
    } else {
      title = book.title;
      subtitle = switch (e.action) {
        _ScanAction.extraCopy => 'Added a copy (now ${book.copies})',
        _ScanAction.moved => 'Moved here',
        _ScanAction.added => switch (book.metadataSource) {
          MetadataSource.pending => 'Looking up details…',
          MetadataSource.manual when book.authors.isEmpty =>
            'Not found online — tap to edit',
          _ => book.authorsText.isEmpty ? 'Saved' : book.authorsText,
        },
      };
    }
    return ListTile(
      dense: true,
      leading: BookCover(url: book?.coverUrl, width: 28),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: book == null
          ? null
          : IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo),
              onPressed: () => _undo(e),
            ),
      onTap: book == null
          ? null
          : () => _withCameraPaused(
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BookDetailScreen(bookId: e.bookId),
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(effectiveScanSettingsProvider);
    final notifier = ref.read(scanSettingsProvider.notifier);
    final books = {
      for (final b in ref.watch(booksProvider).value ?? const <Book>[]) b.id: b,
    };
    final theme = Theme.of(context);

    final scaffold = Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: Column(
        children: [
          // Where scans go.
          Card(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              children: [
                LocationTile(
                  dense: true,
                  locationId: settings.locationId,
                  label: (l) => 'Filing to: ${locationLabel(l)}',
                  pickerTitle: 'File new scans in',
                  onChanged: (l) => notifier.setLocation(l?.id),
                ),
                TagsTile(
                  dense: true,
                  tagIds: settings.tagIds,
                  emptyText: 'No tags for new scans',
                  pickerTitle: 'Tags for new scans',
                  onChanged: notifier.setTags,
                ),
                SwitchListTile(
                  dense: true,
                  secondary: const Icon(Icons.bolt),
                  title: const Text('Quick scan (save without reviewing)'),
                  value: settings.batchMode,
                  onChanged: notifier.setBatchMode,
                ),
              ],
            ),
          ),
          // Camera.
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                      errorBuilder: (context, error) => ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              error.errorCode ==
                                      MobileScannerErrorCode.permissionDenied
                                  ? 'Camera permission is needed to scan. '
                                        'Allow it in Android Settings > Apps > '
                                        'BookCatalog > Permissions.'
                                  : 'Camera unavailable: ${error.errorCode.name}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Aiming guide.
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.8,
                        heightFactor: 0.35,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white70, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: IconButton.filledTonal(
                        tooltip: 'Torch',
                        icon: const Icon(Icons.flashlight_on_outlined),
                        onPressed: () async {
                          try {
                            await _controller.toggleTorch();
                          } catch (e) {
                            debugPrint('Torch failed: $e');
                          }
                        },
                      ),
                    ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 8,
                      child: Text(
                        'Point at the barcode on the back cover',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          shadows: [Shadow(blurRadius: 4)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Fallbacks.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Read printed ISBN'),
                  onPressed: _readPrintedIsbn,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Type ISBN'),
                  onPressed: _typeIsbn,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_note),
                  label: const Text('No ISBN'),
                  onPressed: _noIsbn,
                ),
              ],
            ),
          ),
          // This session's scans.
          Expanded(
            flex: 2,
            child: _session.isEmpty
                ? Center(
                    child: Text(
                      'Scanned books will appear here.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          'This session: ${_session.length}',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      for (final e in _session) _sessionTile(e, books),
                    ],
                  ),
          ),
        ],
      ),
    );

    return Stack(
      children: [
        scaffold,
        // Scan feedback flash over the whole screen; never blocks touches.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: Duration(milliseconds: _flash == null ? 400 : 80),
              color: (_flash ?? Colors.transparent).withValues(
                alpha: _flash == null ? 0 : 0.55,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
