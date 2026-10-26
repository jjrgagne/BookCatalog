import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/search.dart';
import '../../data/models/book.dart';
import '../../data/models/location.dart';
import '../common/widgets.dart';
import 'book_detail_screen.dart';
import 'book_edit_screen.dart';

enum LibrarySort { title, author, recent }

/// Location filter value meaning "books with no (existing) location".
const noLocationFilter = '\u0000none';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.initialLocationId, this.initialTagId});

  /// When opened from Places/Tags, start filtered to that location (or
  /// [noLocationFilter]) or tag.
  final String? initialLocationId;
  final String? initialTagId;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _locationId;
  Set<String> _tagIds = {};
  LibrarySort _sort = LibrarySort.title;
  bool _grid = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _locationId = widget.initialLocationId;
    if (widget.initialTagId != null) _tagIds = {widget.initialTagId!};
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Book> _filter(List<Book> books, Map<String, Location> locations) {
    final result = books.where((b) {
      if (_locationId == noLocationFilter) {
        // Includes books whose location was deleted elsewhere.
        if (locations.containsKey(b.locationId)) return false;
      } else if (_locationId != null && b.locationId != _locationId) {
        return false;
      }
      if (!_tagIds.every(b.tagIds.contains)) return false;
      return bookMatches(b, _query);
    }).toList();

    // Fold each key once rather than on every comparison.
    final titles = {for (final b in result) b.id: foldForSearch(b.title)};
    int byTitle(Book a, Book b) => titles[a.id]!.compareTo(titles[b.id]!);
    switch (_sort) {
      case LibrarySort.title:
        result.sort(byTitle);
      case LibrarySort.author:
        final authors = {
          for (final b in result)
            b.id: foldForSearch(b.authors.firstOrNull ?? '\u{10FFFF}'),
        };
        result.sort((a, b) {
          final c = authors[a.id]!.compareTo(authors[b.id]!);
          return c != 0 ? c : byTitle(a, b);
        });
      case LibrarySort.recent:
        result.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    }
    return result;
  }

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(Book b) => setState(
    () =>
        _selected.contains(b.id) ? _selected.remove(b.id) : _selected.add(b.id),
  );

  void _open(Book b) {
    if (_selecting) return _toggle(b);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: b.id)),
    );
  }

  List<Book> _selectedBooks() => [
    for (final b in ref.read(booksProvider).value ?? <Book>[])
      if (_selected.contains(b.id)) b,
  ];

  Future<void> _moveSelected() async {
    final books = _selectedBooks();
    final picked = await pickAndMoveBooks(context, ref, books);
    if (picked == null || !mounted) return;
    setState(_selected.clear);
    showSnack(
      context,
      'Moved ${books.length} to ${picked.value?.name ?? 'no location'}',
    );
  }

  Future<void> _tagSelected() async {
    final books = _selectedBooks();
    final common = books
        .map((b) => b.tagIds.toSet())
        .reduce((a, b) => a.intersection(b));
    final chosen = await pickTags(
      context,
      ref,
      selected: common,
      title: 'Tags for ${books.length} books',
    );
    if (chosen == null) return;
    await ref
        .read(catalogActionsProvider)
        .retagBooks(
          books,
          add: chosen.difference(common),
          remove: common.difference(chosen),
        );
    if (mounted) setState(_selected.clear);
  }

  Future<void> _deleteSelected() async {
    final books = _selectedBooks();
    final ok = await confirm(
      context,
      title: 'Delete ${books.length} books?',
      message: 'They will be removed from the catalog.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    final repo = ref.read(catalogRepositoryProvider);
    for (final b in books) {
      await repo.deleteBook(b.id);
    }
    if (mounted) setState(_selected.clear);
  }

  Future<void> _refresh() async {
    final books = ref.read(booksProvider).value ?? [];
    final done = await ref
        .read(catalogActionsProvider)
        .completePendingLookups(books);
    if (mounted && done > 0) showSnack(context, 'Looked up $done books');
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    final locations = ref.watch(locationMapProvider);
    final tags = ref.watch(tagMapProvider);
    final all = booksAsync.value ?? const <Book>[];
    final books = _filter(all, locations);
    final pending = all
        .where((b) => b.metadataSource == MetadataSource.pending)
        .length;
    final canPop = Navigator.canPop(context);

    final location = locations[_locationId];
    final locationFilterLabel = switch (_locationId) {
      null => 'Any location',
      noLocationFilter => 'No location',
      _ => location?.name ?? 'Deleted place',
    };

    final appBar = _selecting
        ? AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(_selected.clear),
            ),
            title: Text('${_selected.length} selected'),
            actions: [
              IconButton(
                tooltip: 'Select all',
                icon: const Icon(Icons.select_all),
                onPressed: () =>
                    setState(() => _selected.addAll(books.map((b) => b.id))),
              ),
              IconButton(
                tooltip: 'Move',
                icon: const Icon(Icons.drive_file_move_outline),
                onPressed: _moveSelected,
              ),
              IconButton(
                tooltip: 'Tags',
                icon: const Icon(Icons.label_outline),
                onPressed: _tagSelected,
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _deleteSelected,
              ),
            ],
          )
        : AppBar(
            title: Text(
              canPop && _locationId != null ? locationFilterLabel : 'Library',
            ),
            actions: [
              IconButton(
                tooltip: _grid ? 'List view' : 'Grid view',
                icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
                onPressed: () => setState(() => _grid = !_grid),
              ),
              PopupMenuButton<LibrarySort>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (s) => setState(() => _sort = s),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: LibrarySort.title, child: Text('Title')),
                  PopupMenuItem(
                    value: LibrarySort.author,
                    child: Text('Author'),
                  ),
                  PopupMenuItem(
                    value: LibrarySort.recent,
                    child: Text('Recently added'),
                  ),
                ],
              ),
            ],
          );

    final filters = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          InputChip(
            avatar: Icon(locationIcon(location), size: 18),
            label: Text(locationFilterLabel),
            selected: _locationId != null,
            onPressed: () async {
              final picked = await pickLocation(
                context,
                ref,
                selectedId: _locationId,
                title: 'Show books in',
              );
              if (picked != null) {
                setState(
                  () => _locationId = picked.value?.id ?? noLocationFilter,
                );
              }
            },
            onDeleted: _locationId == null
                ? null
                : () => setState(() => _locationId = null),
          ),
          const SizedBox(width: 8),
          InputChip(
            avatar: const Icon(Icons.label_outline, size: 18),
            label: Text(
              _tagIds.isEmpty
                  ? 'Any tag'
                  : _tagIds.map((t) => tags[t]?.name ?? '?').join(' + '),
            ),
            selected: _tagIds.isNotEmpty,
            onPressed: () async {
              final chosen = await pickTags(
                context,
                ref,
                selected: _tagIds,
                title: 'Show books tagged',
              );
              if (chosen != null) setState(() => _tagIds = chosen);
            },
            onDeleted: _tagIds.isEmpty
                ? null
                : () => setState(() => _tagIds = {}),
          ),
        ],
      ),
    );

    Widget body;
    if (booksAsync.isLoading && all.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (all.isEmpty) {
      body = const _EmptyLibrary();
    } else if (books.isEmpty) {
      body = const Center(child: Text('No books match.'));
    } else if (_grid) {
      body = GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          childAspectRatio: 0.52,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: books.length,
        itemBuilder: (context, i) {
          final b = books[i];
          final selected = _selected.contains(b.id);
          return InkWell(
            onTap: () => _open(b),
            onLongPress: () => _toggle(b),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    BookCover(url: b.coverUrl, width: 110),
                    if (selected)
                      const Positioned(
                        right: 4,
                        top: 4,
                        child: Icon(Icons.check_circle),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  b.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      );
    } else {
      body = ListView.builder(
        itemCount: books.length,
        itemBuilder: (context, i) {
          final b = books[i];
          final loc = locations[b.locationId];
          final selected = _selected.contains(b.id);
          return ListTile(
            selected: selected,
            leading: selected
                ? const SizedBox(
                    width: 48,
                    child: Icon(Icons.check_circle, size: 32),
                  )
                : BookCover(url: b.coverUrl),
            title: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (b.authors.isNotEmpty)
                  Text(
                    b.authorsText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Row(
                  children: [
                    Icon(locationIcon(loc), size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        loc?.name ?? 'No location',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (b.copies > 1) Text('  ×${b.copies}'),
                  ],
                ),
                if (b.tagIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TagChips(tagIds: b.tagIds),
                  ),
              ],
            ),
            isThreeLine: true,
            onTap: () => _open(b),
            onLongPress: () => _toggle(b),
          );
        },
      );
    }

    return Scaffold(
      appBar: appBar,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SearchBar(
              controller: _search,
              hintText: 'Search title, author, ISBN, notes',
              leading: const Icon(Icons.search),
              trailing: [
                if (_query.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
              ],
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          filters,
          if (pending > 0)
            MaterialBanner(
              content: Text(
                '$pending ${pending == 1 ? 'book is' : 'books are'} '
                'waiting for details (offline?).',
              ),
              leading: const Icon(Icons.cloud_off),
              actions: [
                TextButton(onPressed: _refresh, child: const Text('Retry')),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                books.length == all.length
                    ? '${all.length} books'
                    : '${books.length} of ${all.length} books',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(onRefresh: _refresh, child: body),
          ),
        ],
      ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
              tooltip: 'Add book manually',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BookEditScreen(
                    initialLocationId: switch (_locationId) {
                      noLocationFilter => null,
                      null =>
                        ref.read(effectiveScanSettingsProvider).locationId,
                      final id => id,
                    },
                  ),
                ),
              ),
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const SizedBox(height: 80),
      Icon(
        Icons.auto_stories_outlined,
        size: 72,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 16),
      Text(
        'No books yet',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'Open the Scan tab and point the camera at a book\'s barcode, '
          'or tap + to add one by hand.',
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}
