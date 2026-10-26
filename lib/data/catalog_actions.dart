import '../core/isbn.dart';
import 'models/book.dart';
import 'models/book_metadata.dart';
import 'models/ids.dart';
import 'models/location.dart';
import 'models/tag.dart';
import 'repositories/catalog_repository.dart';
import 'services/metadata_service.dart';

/// Catalog operations that span several records (moves, returns, deletes
/// that must update books, background lookups).
class CatalogActions {
  CatalogActions(this.repo, this.metadata, {this.userId});

  final CatalogRepository repo;
  final MetadataService metadata;
  final String? userId;

  /// Creates a book from a scan. Without [details] the book is saved as
  /// pending and filled in later by [completePendingLookups].
  Book newBookFromScan(
    String isbn13, {
    BookMetadata? details,
    String? locationId,
    List<String> tagIds = const [],
  }) {
    final now = DateTime.now();
    return Book(
      id: generateId(),
      isbn13: isbn13,
      isbn10: details?.isbn10 ?? toIsbn10(isbn13),
      title: details?.title ?? 'ISBN ${displayIsbn(isbn13)}',
      subtitle: details?.subtitle,
      authors: details?.authors ?? const [],
      publisher: details?.publisher,
      publishedYear: details?.publishedYear,
      coverUrl: details?.coverUrl,
      locationId: locationId,
      tagIds: tagIds,
      metadataSource: details?.source ?? MetadataSource.pending,
      addedBy: userId,
      addedAt: now,
      updatedAt: now,
    );
  }

  /// Applies looked-up [details] to an existing book, keeping user fields.
  static Book applyMetadata(Book book, BookMetadata details) => book.copyWith(
    isbn10: details.isbn10 ?? book.isbn10,
    title: details.title,
    subtitle: details.subtitle,
    authors: details.authors,
    publisher: details.publisher,
    publishedYear: details.publishedYear,
    coverUrl: details.coverUrl,
    metadataSource: details.source,
  );

  /// Looks up every pending book. Returns how many were completed.
  /// Books unknown to both services become manual so they stop retrying.
  Future<int> completePendingLookups(List<Book> books) async {
    var done = 0;
    for (final book in books.where(
      (b) => b.metadataSource == MetadataSource.pending && b.isbn13 != null,
    )) {
      try {
        final details = await metadata.lookup(book.isbn13!);
        await repo.saveBook(
          details == null
              ? book.copyWith(metadataSource: MetadataSource.manual)
              : applyMetadata(book, details),
        );
        done++;
      } on LookupUnavailableException {
        break; // Still offline; try again later.
      }
    }
    return done;
  }

  /// Moves books to [target] (null = no location). When a book goes from a
  /// room to a person, the room is remembered so it can be returned later.
  Future<void> moveBooks(
    List<Book> books,
    Location? target,
    Map<String, Location> locations,
  ) {
    return repo.saveBooks([
      for (final b in books) moveBook(b, target, locations),
    ]);
  }

  static Book moveBook(
    Book book,
    Location? target,
    Map<String, Location> locations,
  ) {
    final current = locations[book.locationId];
    String? previous;
    if (target?.isPerson ?? false) {
      // Lending: remember the room (or keep the one already remembered when
      // passing a book from one person to another).
      previous = (current != null && !current.isPerson)
          ? current.id
          : book.previousLocationId;
    }
    return book.copyWith(locationId: target?.id, previousLocationId: previous);
  }

  /// Where Return would send [book], or null if it isn't on loan or the room
  /// it came from no longer exists.
  static Location? returnTarget(Book book, Map<String, Location> locations) {
    final current = locations[book.locationId];
    if (current == null || !current.isPerson) return null;
    final room = locations[book.previousLocationId];
    return (room != null && !room.isPerson) ? room : null;
  }

  Future<void> deleteLocation(
    Location location,
    List<Book> books, {
    Location? moveTo,
    required Map<String, Location> locations,
  }) async {
    final affected = books
        .where(
          (b) =>
              b.locationId == location.id ||
              b.previousLocationId == location.id,
        )
        .toList();
    String? keptPrevious(Book b) =>
        b.previousLocationId == location.id ? null : b.previousLocationId;
    await repo.saveBooks([
      for (final b in affected)
        if (b.locationId == location.id)
          b.copyWith(
            locationId: moveTo?.id,
            // Only books moved to a person keep a room to return to.
            previousLocationId: (moveTo?.isPerson ?? false)
                ? keptPrevious(b)
                : null,
          )
        else
          b.copyWith(previousLocationId: null),
    ]);
    await repo.deleteLocation(location.id);
  }

  Future<void> deleteTag(Tag tag, List<Book> books) async {
    await repo.saveBooks([
      for (final b in books.where((b) => b.tagIds.contains(tag.id)))
        b.copyWith(tagIds: b.tagIds.where((t) => t != tag.id).toList()),
    ]);
    await repo.deleteTag(tag.id);
  }

  /// Adds [add] and removes [remove] tags on each book.
  Future<void> retagBooks(
    List<Book> books, {
    Set<String> add = const {},
    Set<String> remove = const {},
  }) {
    return repo.saveBooks([
      for (final b in books)
        b.copyWith(tagIds: {...b.tagIds, ...add}.difference(remove).toList()),
    ]);
  }

  /// Copies everything from another catalog (e.g. this phone's books into a
  /// newly joined household).
  Future<void> importAll({
    required List<Book> books,
    required List<Location> locations,
    required List<Tag> tags,
  }) async {
    await repo.saveLocations(locations);
    for (final t in tags) {
      await repo.saveTag(t);
    }
    await repo.saveBooks(books);
  }
}

/// Finds a book with the same ISBN, if any.
Book? findByIsbn(Iterable<Book> books, String isbn13) {
  for (final b in books) {
    if (b.isbn13 == isbn13) return b;
  }
  return null;
}
