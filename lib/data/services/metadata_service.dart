import 'package:http/http.dart' as http;

import '../models/book_metadata.dart';
import 'google_books.dart';
import 'open_library.dart';

/// Thrown when no lookup service could be reached (e.g. offline).
class LookupUnavailableException implements Exception {
  const LookupUnavailableException(this.cause);
  final Object cause;

  @override
  String toString() => 'Book lookup unavailable: $cause';
}

/// Looks up a book on Open Library first, then fills gaps from Google Books.
class MetadataService {
  MetadataService({http.Client? client})
    : this.withClients(
        OpenLibraryClient(client ?? http.Client()),
        GoogleBooksClient(client ?? http.Client()),
      );

  MetadataService.withClients(this._openLibrary, this._googleBooks);

  final OpenLibraryClient _openLibrary;
  final GoogleBooksClient _googleBooks;

  /// Returns merged metadata, or null if neither service knows the book.
  /// Throws [LookupUnavailableException] if both services failed to respond.
  Future<BookMetadata?> lookup(String isbn13) async {
    Object? olError;
    BookMetadata? ol;
    try {
      ol = await _openLibrary.lookup(isbn13);
    } catch (e) {
      olError = e;
    }
    if (ol != null && ol.isComplete) return ol;

    BookMetadata? gb;
    try {
      gb = await _googleBooks.lookup(isbn13);
    } catch (e) {
      if (olError != null) throw LookupUnavailableException(e);
    }
    if (ol != null) return ol.mergedWith(gb);
    return gb;
  }
}
