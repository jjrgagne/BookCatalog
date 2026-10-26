import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/catalog_actions.dart';
import '../../data/models/book.dart';
import '../common/widgets.dart';
import 'book_edit_screen.dart';

class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider).value ?? const <Book>[];
    final book = books.where((b) => b.id == bookId).firstOrNull;
    if (book == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('This book is no longer in the catalog.'),
        ),
      );
    }
    final locations = ref.watch(locationMapProvider);
    final location = locations[book.locationId];
    final returnTo = CatalogActions.returnTarget(book, locations);
    final repo = ref.read(catalogRepositoryProvider);
    final theme = Theme.of(context);

    Future<void> editNotes() async {
      final notes = await showTextDialog(
        context,
        title: 'Notes',
        initial: book.notes,
        multiline: true,
      );
      if (notes != null) await repo.saveBook(book.copyWith(notes: notes));
    }

    Future<void> lookUpAgain() async {
      final outcome = await ref
          .read(catalogActionsProvider)
          .lookUpAndApply(book);
      if (!context.mounted) return;
      final message = switch (outcome) {
        LookupOutcome.updated => 'Details updated.',
        LookupOutcome.notFound => 'No details found online.',
        LookupOutcome.offline => 'Could not reach the book services. Offline?',
        LookupOutcome.skipped => 'Already looking this book up…',
      };
      showSnack(context, message);
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BookEditScreen(book: book)),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'lookup') await lookUpAgain();
              if (v == 'delete' && context.mounted) {
                final ok = await confirm(
                  context,
                  title: 'Delete this book?',
                  message: book.title,
                  action: 'Delete',
                  destructive: true,
                );
                if (ok) {
                  await repo.deleteBook(book.id);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [
              if (book.isbn13 != null)
                const PopupMenuItem(
                  value: 'lookup',
                  child: Text('Look up details again'),
                ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(url: book.coverUrl, width: 110),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title, style: theme.textTheme.titleLarge),
                    if (book.subtitle != null && book.subtitle!.isNotEmpty)
                      Text(book.subtitle!, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    if (book.authors.isNotEmpty)
                      Text(book.authorsText, style: theme.textTheme.bodyLarge),
                    if (book.publisher != null || book.publishedYear != null)
                      Text(
                        [
                          book.publisher,
                          book.publishedYear?.toString(),
                        ].whereType<String>().join(' · '),
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (book.metadataSource == MetadataSource.pending)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Look up details'),
                          onPressed: lookUpAgain,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(locationIcon(location)),
                  title: Text(locationLabel(location)),
                  subtitle: returnTo == null
                      ? null
                      : Text('Usually in ${returnTo.name}'),
                  trailing: TextButton(
                    onPressed: () => pickAndMoveBooks(context, ref, [book]),
                    child: Text(
                      location?.isPerson ?? false ? 'Move' : 'Move / Lend',
                    ),
                  ),
                ),
                if (returnTo != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.keyboard_return),
                        label: Text('Return to ${returnTo.name}'),
                        onPressed: () async {
                          await repo.saveBook(
                            CatalogActions.moveBook(book, returnTo, locations),
                          );
                          if (context.mounted) {
                            showSnack(context, 'Returned to ${returnTo.name}');
                          }
                        },
                      ),
                    ),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      TagsTile(
                        tagIds: book.tagIds,
                        onChanged: (t) =>
                            repo.saveBook(book.copyWith(tagIds: t)),
                      ),
                      CopiesTile(
                        copies: book.copies,
                        onChanged: (c) =>
                            repo.saveBook(book.copyWith(copies: c)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notes),
              title: const Text('Notes'),
              subtitle: Text(
                book.notes.isEmpty ? 'Tap to add notes' : book.notes,
              ),
              onTap: editNotes,
            ),
          ),
          const SizedBox(height: 16),
          // Details typed in or never found: offer web searches by ISBN.
          if (book.isbn13 != null &&
              (book.metadataSource == MetadataSource.manual ||
                  book.metadataSource == MetadataSource.pending)) ...[
            WebSearchButtons(isbn13: book.isbn13!),
            const SizedBox(height: 8),
          ],
          if (book.isbn13 != null)
            Text('ISBN-13: ${book.isbn13}', style: theme.textTheme.bodySmall),
          if (book.isbn10 != null)
            Text('ISBN-10: ${book.isbn10}', style: theme.textTheme.bodySmall),
          Text(
            'Added ${MaterialLocalizations.of(context).formatMediumDate(book.addedAt)}'
            '${book.metadataSource == MetadataSource.manual ? '' : ' · details from ${_sourceName(book.metadataSource)}'}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _sourceName(MetadataSource s) => switch (s) {
  MetadataSource.openlibrary => 'Open Library',
  MetadataSource.google => 'Google Books',
  MetadataSource.crossref => 'Crossref',
  MetadataSource.manual => 'manual entry',
  MetadataSource.pending => 'pending lookup',
};
