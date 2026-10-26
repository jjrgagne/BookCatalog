import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/isbn.dart';
import '../../data/models/book.dart';
import '../../data/models/book_metadata.dart';
import '../../data/services/metadata_service.dart';
import '../catalog/book_edit_screen.dart';
import '../catalog/library_screen.dart';
import '../common/widgets.dart';

/// Looks up a scanned ISBN and lets the user confirm before saving.
/// Returns the saved book, or null if discarded.
Future<Book?> showScanResultSheet(
  BuildContext context, {
  required String isbn13,
}) {
  return showModalBottomSheet<Book>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ScanResultSheet(isbn13: isbn13),
  );
}

enum _Status { loading, found, notFound, offline }

class _ScanResultSheet extends ConsumerStatefulWidget {
  const _ScanResultSheet({required this.isbn13});

  final String isbn13;

  @override
  ConsumerState<_ScanResultSheet> createState() => _ScanResultSheetState();
}

class _ScanResultSheetState extends ConsumerState<_ScanResultSheet> {
  _Status _status = _Status.loading;
  BookMetadata? _details;
  late String? _locationId;
  late List<String> _tagIds;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(scanSettingsProvider);
    _locationId = settings.locationId;
    _tagIds = [...settings.tagIds];
    _lookup();
  }

  Future<void> _lookup() async {
    setState(() => _status = _Status.loading);
    try {
      final details = await ref
          .read(metadataServiceProvider)
          .lookup(widget.isbn13);
      if (!mounted) return;
      setState(() {
        _details = details;
        _status = details == null ? _Status.notFound : _Status.found;
      });
    } on LookupUnavailableException {
      if (mounted) setState(() => _status = _Status.offline);
    }
  }

  Future<void> _save() async {
    var book = ref
        .read(catalogActionsProvider)
        .newBookFromScan(
          widget.isbn13,
          details: _details,
          locationId: _locationId,
          tagIds: _tagIds,
        );
    // Not found online: don't keep retrying; offline: stays pending.
    if (_status == _Status.notFound) {
      book = book.copyWith(metadataSource: MetadataSource.manual);
    }
    await ref.read(catalogRepositoryProvider).saveBook(book);
    if (mounted) Navigator.pop(context, book);
  }

  Future<void> _enterManually() async {
    final saved = await Navigator.push<Book>(
      context,
      MaterialPageRoute(
        builder: (_) => BookEditScreen(
          initialIsbn: widget.isbn13,
          initialLocationId: _locationId,
          initialTagIds: _tagIds,
        ),
      ),
    );
    if (mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = ref.watch(locationMapProvider)[_locationId];
    final d = _details;

    final Widget header = switch (_status) {
      _Status.loading => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      _Status.found => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCover(url: d!.coverUrl, width: 80),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.title, style: theme.textTheme.titleMedium),
                if (d.subtitle != null) Text(d.subtitle!),
                const SizedBox(height: 4),
                if (d.authors.isNotEmpty) Text(d.authors.join(', ')),
                if (d.publishedYear != null || d.publisher != null)
                  Text(
                    [
                      d.publisher,
                      d.publishedYear?.toString(),
                    ].whereType<String>().join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
      _Status.notFound => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.search_off),
            title: Text('Not found in any book database'),
            subtitle: Text(
              'Look it up on the web and type the details in, or save with '
              'just the ISBN.',
            ),
          ),
          WebSearchButtons(isbn13: widget.isbn13),
        ],
      ),
      _Status.offline => ListTile(
        leading: const Icon(Icons.cloud_off),
        title: const Text("Can't reach the book services"),
        subtitle: const Text(
          'Save now and the details will be filled in when you are online.',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _lookup,
        ),
      ),
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ISBN ${displayIsbn(widget.isbn13)}',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            header,
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(locationIcon(location)),
              title: Text(locationLabel(location)),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final picked = await pickLocation(
                  context,
                  ref,
                  selectedId: _locationId,
                );
                if (picked != null) {
                  setState(() => _locationId = picked.value?.id);
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.label_outline),
              title: _tagIds.isEmpty
                  ? const Text('No tags')
                  : TagChips(tagIds: _tagIds),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final chosen = await pickTags(context, ref, selected: _tagIds);
                if (chosen != null) setState(() => _tagIds = chosen.toList());
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Discard'),
                ),
                const Spacer(),
                if (_status == _Status.notFound)
                  TextButton(
                    onPressed: _enterManually,
                    child: const Text('Enter details'),
                  ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _status == _Status.loading ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
