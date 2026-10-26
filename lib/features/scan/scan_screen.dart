import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import '../../core/isbn.dart';
import '../../data/catalog_actions.dart';
import '../../data/models/book.dart';
import '../../data/services/metadata_service.dart';
import '../catalog/book_detail_screen.dart';
import '../catalog/book_edit_screen.dart';
import '../catalog/library_screen.dart';
import '../common/widgets.dart';
import 'ocr.dart';
import 'scan_result_sheet.dart';

/// One scan in the current session, shown in the running list.
class _SessionEntry {
  _SessionEntry(this.bookId, this.isbn13, this.status);
  final String bookId;
  final String isbn13;
  String status;
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

  /// Full-screen colour flash: green = saved, amber = already in catalog.
  Color? _flash;
  Timer? _flashTimer;

  void _flashScreen(Color color) {
    _flashTimer?.cancel();
    setState(() => _flash = color);
    _flashTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  String? _lastIsbn;
  DateTime _lastAt = DateTime(2000);
  final List<_SessionEntry> _session = [];

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(_controller.start());
  }

  @override
  void didUpdateWidget(ScanScreen old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      unawaited(widget.active ? _controller.start() : _controller.stop());
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    unawaited(_controller.dispose());
    super.dispose();
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
    _busy = true;
    try {
      await HapticFeedback.mediumImpact();
      await SystemSound.play(SystemSoundType.click);
      final settings = ref.read(scanSettingsProvider);
      final books = ref.read(booksProvider).value ?? const <Book>[];
      final existing = findByIsbn(books, isbn13);
      if (existing != null) {
        await _handleDuplicate(existing, settings.locationId);
        return;
      }
      if (settings.batchMode) {
        await _saveBatch(isbn13, settings);
      } else {
        await _controller.stop();
        if (!mounted) return;
        final saved = await showScanResultSheet(context, isbn13: isbn13);
        if (saved != null) {
          _session.insert(0, _SessionEntry(saved.id, isbn13, 'Saved'));
          if (mounted) _flashScreen(Colors.green);
        }
        if (mounted && widget.active) await _controller.start();
      }
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveBatch(String isbn13, ScanSettings settings) async {
    final actions = ref.read(catalogActionsProvider);
    final repo = ref.read(catalogRepositoryProvider);
    // Save immediately so scanning a shelf never waits on the network.
    final book = actions.newBookFromScan(
      isbn13,
      locationId: settings.locationId,
      tagIds: settings.tagIds,
    );
    await repo.saveBook(book);
    final entry = _SessionEntry(book.id, isbn13, 'Looking up…');
    setState(() => _session.insert(0, entry));
    _flashScreen(Colors.green);

    unawaited(() async {
      try {
        final details = await ref.read(metadataServiceProvider).lookup(isbn13);
        if (details == null) {
          await repo.saveBook(
            book.copyWith(metadataSource: MetadataSource.manual),
          );
          entry.status = 'Not found online — tap to edit';
        } else {
          await repo.saveBook(CatalogActions.applyMetadata(book, details));
          entry.status = details.title;
        }
      } on LookupUnavailableException {
        entry.status = 'Saved — details when online';
      }
      if (mounted) setState(() {});
    }());
  }

  Future<void> _handleDuplicate(
    Book existing,
    String? currentLocationId,
  ) async {
    _flashScreen(Colors.amber);
    await _controller.stop();
    if (!mounted) return;
    final locations = ref.read(locationMapProvider);
    final here = locations[currentLocationId];
    final sameLocation = existing.locationId == currentLocationId;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Already in the catalog'),
        content: Text(
          '"${existing.title}"\n${locationLabel(locations[existing.locationId])}'
          '${existing.copies > 1 ? ' · ${existing.copies} copies' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'copy'),
            child: const Text('Add a copy'),
          ),
          if (!sameLocation)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'move'),
              child: Text('Move to ${here?.name ?? 'no location'}'),
            ),
        ],
      ),
    );
    final repo = ref.read(catalogRepositoryProvider);
    if (choice == 'copy') {
      await repo.saveBook(existing.copyWith(copies: existing.copies + 1));
      _session.insert(
        0,
        _SessionEntry(
          existing.id,
          existing.isbn13!,
          'Another copy of ${existing.title}',
        ),
      );
    } else if (choice == 'move') {
      await repo.saveBook(CatalogActions.moveBook(existing, here, locations));
      _session.insert(
        0,
        _SessionEntry(
          existing.id,
          existing.isbn13!,
          'Moved: ${existing.title}',
        ),
      );
    }
    if (mounted && widget.active) await _controller.start();
  }

  Future<void> _readPrintedIsbn() async {
    await _controller.stop();
    try {
      final OcrResult? ocr;
      try {
        ocr = await captureAndReadIsbn();
      } on PlatformException catch (e) {
        if (mounted) {
          showSnack(context, 'Camera unavailable: ${e.message ?? e.code}');
        }
        return;
      }
      if (!mounted || ocr == null) return;
      final result = ocr;
      String? isbn;
      if (result.isbns.length == 1) {
        isbn = result.isbns.single;
      } else if (result.isbns.length > 1) {
        isbn = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Which ISBN?'),
            children: [
              for (final i in result.isbns)
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
      }
      if (isbn != null && mounted) {
        final ok = await confirm(
          context,
          title: 'Use this ISBN?',
          message: displayIsbn(isbn),
          action: 'Look up',
        );
        if (ok) await _handleIsbn(isbn);
      }
    } finally {
      if (mounted && widget.active && !_busy) await _controller.start();
    }
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
    await _controller.stop();
    final settings = ref.read(scanSettingsProvider);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookEditScreen(
          initialLocationId: settings.locationId,
          initialTagIds: settings.tagIds,
        ),
      ),
    );
    if (mounted && widget.active) await _controller.start();
  }

  Future<void> _undo(_SessionEntry entry) async {
    await ref.read(catalogRepositoryProvider).deleteBook(entry.bookId);
    setState(() => _session.remove(entry));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(scanSettingsProvider);
    final locations = ref.watch(locationMapProvider);
    final location = locations[settings.locationId];
    final notifier = ref.read(scanSettingsProvider.notifier);
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
                ListTile(
                  dense: true,
                  leading: Icon(locationIcon(location)),
                  title: Text('Filing to: ${locationLabel(location)}'),
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () async {
                    final picked = await pickLocation(
                      context,
                      ref,
                      selectedId: settings.locationId,
                      title: 'File new scans in',
                    );
                    if (picked != null) notifier.setLocation(picked.value?.id);
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.label_outline),
                  title: settings.tagIds.isEmpty
                      ? const Text('No tags for new scans')
                      : TagChips(tagIds: settings.tagIds),
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () async {
                    final chosen = await pickTags(
                      context,
                      ref,
                      selected: settings.tagIds,
                      title: 'Tags for new scans',
                    );
                    if (chosen != null) notifier.setTags(chosen.toList());
                  },
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
                        onPressed: _controller.toggleTorch,
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
                      for (final e in _session)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.check_circle_outline),
                          title: Text(
                            e.status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(displayIsbn(e.isbn13)),
                          trailing:
                              e.status.startsWith('Another copy') ||
                                  e.status.startsWith('Moved')
                              ? null
                              : IconButton(
                                  tooltip: 'Undo',
                                  icon: const Icon(Icons.undo),
                                  onPressed: () => _undo(e),
                                ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  BookDetailScreen(bookId: e.bookId),
                            ),
                          ),
                        ),
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
