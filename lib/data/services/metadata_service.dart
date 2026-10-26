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

/// Checks that a cover URL really serves an image.
typedef CoverCheck = Future<bool> Function(String url);

/// Looks a book up in several free sources, in order: Open Library, Google
/// Books (ISBN-13 then ISBN-10), Open Library's search index, then Crossref.
///
/// Text details and the cover are chosen independently: details come from
/// the first source that has them (later sources fill gaps), while the cover
/// is the first candidate from *any* source that actually loads, with Open
/// Library's cover-by-ISBN as the last resort. So a book can get its details
/// from Open Library and its cover from Google Books.
class MetadataService {
  factory MetadataService({http.Client? client, CoverCheck? coverCheck}) {
    final c = client ?? http.Client();
    return MetadataService.withSources(
      _defaultSources(c),
      coverCheck: coverCheck ?? _httpCoverCheck(c),
    );
  }

  MetadataService.withSources(this._sources, {required this.coverCheck});

  static List<LookupSource> _defaultSources(http.Client client) => [
    OpenLibraryClient(client).lookup,
    GoogleBooksClient(client).lookup,
    OpenLibrarySearchClient(client).lookup,
    CrossrefClient(client).lookup,
  ];

  /// An image is "real" if it returns 200 with an image type and isn't a
  /// tiny placeholder (some services return a 1×1 pixel for missing covers).
  static CoverCheck _httpCoverCheck(http.Client client) => (url) async {
    try {
      final r = await client
          .get(Uri.parse(url), headers: {'User-Agent': userAgent})
          .timeout(const Duration(seconds: 8));
      final type = r.headers['content-type'] ?? '';
      return r.statusCode == 200 &&
          type.startsWith('image/') &&
          r.bodyBytes.length > 1000;
    } catch (_) {
      return false;
    }
  };

  final List<LookupSource> _sources;
  final CoverCheck coverCheck;

  /// Returns merged metadata, or null if no source knows the book.
  /// Throws [LookupUnavailableException] if every source failed to respond.
  Future<BookMetadata?> lookup(String isbn13) async {
    BookMetadata? details;
    String? cover;
    final tried = <String>{};
    Object? lastError;
    var failures = 0;

    Future<void> considerCover(String? url) async {
      if (cover != null || url == null || !tried.add(url)) return;
      if (await coverCheck(url)) cover = url;
    }

    for (final source in _sources) {
      try {
        final found = await source(isbn13);
        details = details == null ? found : details.mergedWith(found);
        await considerCover(found?.coverUrl);
      } catch (e) {
        failures++;
        lastError = e;
      }
      if (details != null && details.hasFullDetails && cover != null) break;
    }

    if (details == null) {
      if (failures == _sources.length) {
        throw LookupUnavailableException(lastError!);
      }
      return null;
    }
    await considerCover(openLibraryCoverByIsbn(isbn13));
    return details.withCover(cover);
  }
}
