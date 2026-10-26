import 'package:http/http.dart' as http;

import '../models/book_metadata.dart';
import 'backup_sources.dart';
import 'google_books.dart';
import 'open_library.dart';

/// Thrown when no lookup service could be reached (e.g. offline).
class LookupUnavailableException implements Exception {
  const LookupUnavailableException(this.cause);
  final Object cause;

  @override
  String toString() => 'Book lookup unavailable: $cause';
}

typedef LookupSource = Future<BookMetadata?> Function(String isbn13);

/// Looks a book up in several free sources, in order, until the details are
/// complete: Open Library, Google Books (ISBN-13 then ISBN-10), Open
/// Library's search index, then Crossref. Later sources only fill gaps.
class MetadataService {
  MetadataService({http.Client? client})
    : this.withSources(_defaultSources(client ?? http.Client()));

  MetadataService.withSources(this._sources);

  static List<LookupSource> _defaultSources(http.Client client) => [
    OpenLibraryClient(client).lookup,
    GoogleBooksClient(client).lookup,
    OpenLibrarySearchClient(client).lookup,
    CrossrefClient(client).lookup,
  ];

  final List<LookupSource> _sources;

  /// Returns merged metadata, or null if no source knows the book.
  /// Throws [LookupUnavailableException] if every source failed to respond.
  Future<BookMetadata?> lookup(String isbn13) async {
    BookMetadata? result;
    Object? lastError;
    var failures = 0;
    for (final source in _sources) {
      try {
        final found = await source(isbn13);
        result = result == null ? found : result.mergedWith(found);
      } catch (e) {
        failures++;
        lastError = e;
      }
      if (result != null && result.isComplete) break;
    }
    if (result == null && failures == _sources.length) {
      throw LookupUnavailableException(lastError!);
    }
    // Many books without a cover in the metadata still have one here.
    if (result != null && result.coverUrl == null) {
      result = result.mergedWith(
        BookMetadata(
          isbn13: isbn13,
          title: '',
          source: result.source,
          coverUrl: openLibraryCoverByIsbn(isbn13),
        ),
      );
    }
    return result;
  }
}
