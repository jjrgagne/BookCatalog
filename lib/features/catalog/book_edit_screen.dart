import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/isbn.dart';
import '../../data/catalog_actions.dart';
import '../../data/models/book.dart';
import '../../data/models/ids.dart';
import '../common/widgets.dart';
import 'library_screen.dart';

/// Edits an existing book, or creates one by hand (no ISBN needed).
class BookEditScreen extends ConsumerStatefulWidget {
  const BookEditScreen({
    super.key,
    this.book,
    this.initialIsbn,
    this.initialLocationId,
    this.initialTagIds = const [],
  });

  final Book? book;

  /// Pre-filled ISBN when a scan found no details online.
  final String? initialIsbn;
  final String? initialLocationId;
  final List<String> initialTagIds;

  @override
  ConsumerState<BookEditScreen> createState() => _BookEditScreenState();
}

class _BookEditScreenState extends ConsumerState<BookEditScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late final TextEditingController _authors;
  late final TextEditingController _publisher;
  late final TextEditingController _year;
  late final TextEditingController _isbn;
  late final TextEditingController _notes;
  late String? _locationId;
  late List<String> _tagIds;
  late int _copies;

  bool get _isNew => widget.book == null;

  @override
  void initState() {
    super.initState();
    final b = widget.book;
    _title = TextEditingController(text: b?.title ?? '');
    _subtitle = TextEditingController(text: b?.subtitle ?? '');
    _authors = TextEditingController(text: b?.authors.join(', ') ?? '');
    _publisher = TextEditingController(text: b?.publisher ?? '');
    _year = TextEditingController(text: b?.publishedYear?.toString() ?? '');
    _isbn = TextEditingController(text: b?.isbn13 ?? widget.initialIsbn ?? '');
    _notes = TextEditingController(text: b?.notes ?? '');
    _locationId = b?.locationId ?? widget.initialLocationId;
    _tagIds = [...(b?.tagIds ?? widget.initialTagIds)];
    _copies = b?.copies ?? 1;
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _subtitle,
      _authors,
      _publisher,
      _year,
      _isbn,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _blankToNull(String s) => s.trim().isEmpty ? null : s.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final isbnText = _isbn.text.trim();
    final isbn13 = isbnText.isEmpty ? null : toIsbn13(isbnText);
    final books = ref.read(booksProvider).value ?? const <Book>[];

    if (isbn13 != null && isbn13 != widget.book?.isbn13) {
      final existing = findByIsbn(books, isbn13);
      if (existing != null && existing.id != widget.book?.id) {
        final location = ref.read(locationMapProvider)[existing.locationId];
        final ok = await confirm(
          context,
          title: 'Already in the catalog',
          message:
              '"${existing.title}" (${locationLabel(location)}) has the same '
              'ISBN. Save this as a separate entry anyway?',
          action: 'Save anyway',
        );
        if (!ok) return;
      }
    }

    final now = DateTime.now();
    final authors = _authors.text
        .split(RegExp(r'[,;]'))
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList();
    final base =
        widget.book ??
        Book(
          id: generateId(),
          title: '',
          addedBy: ref.read(authStateProvider).value?.uid,
          addedAt: now,
          updatedAt: now,
        );
    final book = base.copyWith(
      title: _title.text.trim(),
      subtitle: _blankToNull(_subtitle.text),
      authors: authors,
      publisher: _blankToNull(_publisher.text),
      publishedYear: int.tryParse(_year.text.trim()),
      isbn13: isbn13,
      isbn10: isbn13 == null ? null : toIsbn10(isbn13),
      notes: _notes.text.trim(),
      copies: _copies,
      tagIds: _tagIds,
      metadataSource: base.metadataSource == MetadataSource.pending
          ? MetadataSource.manual
          : base.metadataSource,
    );
    final moved = book.locationId == _locationId
        ? book
        : CatalogActions.moveBook(
            book,
            ref.read(locationMapProvider)[_locationId],
            ref.read(locationMapProvider),
          );
    await ref.read(catalogRepositoryProvider).saveBook(moved);
    if (mounted) Navigator.pop(context, moved);
  }

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(locationMapProvider);
    final location = locations[_locationId];
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add book' : 'Edit book'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title *'),
              textCapitalization: TextCapitalization.words,
              autofocus: _isNew && widget.initialIsbn == null,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
            ),
            TextFormField(
              controller: _subtitle,
              decoration: const InputDecoration(labelText: 'Subtitle'),
              textCapitalization: TextCapitalization.sentences,
            ),
            TextFormField(
              controller: _authors,
              decoration: const InputDecoration(
                labelText: 'Authors',
                helperText: 'Separate several authors with commas',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            TextFormField(
              controller: _publisher,
              decoration: const InputDecoration(labelText: 'Publisher'),
              textCapitalization: TextCapitalization.words,
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _year,
                    decoration: const InputDecoration(labelText: 'Year'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final y = int.tryParse(v.trim());
                      return (y == null || y < 1400 || y > 2100)
                          ? 'Enter a year'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _isbn,
                    decoration: const InputDecoration(
                      labelText: 'ISBN (optional)',
                    ),
                    keyboardType: TextInputType.text,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      return toIsbn13(v) == null
                          ? 'Not a valid ISBN-10 or ISBN-13'
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(locationIcon(location)),
              title: Text(locationLabel(location)),
              trailing: const Icon(Icons.chevron_right),
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
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final chosen = await pickTags(context, ref, selected: _tagIds);
                if (chosen != null) setState(() => _tagIds = chosen.toList());
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.layers_outlined),
              title: Text(_copies == 1 ? '1 copy' : '$_copies copies'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: _copies <= 1
                        ? null
                        : () => setState(() => _copies--),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => setState(() => _copies++),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
