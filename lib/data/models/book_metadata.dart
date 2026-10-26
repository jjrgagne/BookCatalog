import 'book.dart';

/// Details about a book returned by a metadata service.
class BookMetadata {
  const BookMetadata({
    required this.isbn13,
    required this.title,
    required this.source,
    this.isbn10,
    this.subtitle,
    this.authors = const [],
    this.publisher,
    this.publishedYear,
    this.coverUrl,
  });

  final String isbn13;
  final String? isbn10;
  final String title;
  final String? subtitle;
  final List<String> authors;
  final String? publisher;
  final int? publishedYear;
  final String? coverUrl;
  final MetadataSource source;

  /// Fills fields missing here from [other] (used to merge two sources).
  BookMetadata mergedWith(BookMetadata? other) {
    if (other == null) return this;
    return BookMetadata(
      isbn13: isbn13,
      isbn10: isbn10 ?? other.isbn10,
      title: title.isNotEmpty ? title : other.title,
      subtitle: subtitle ?? other.subtitle,
      authors: authors.isNotEmpty ? authors : other.authors,
      publisher: publisher ?? other.publisher,
      publishedYear: publishedYear ?? other.publishedYear,
      coverUrl: coverUrl ?? other.coverUrl,
      source: source,
    );
  }

  bool get isComplete =>
      title.isNotEmpty &&
      authors.isNotEmpty &&
      coverUrl != null &&
      publishedYear != null;
}

/// Extracts a 4-digit year from strings like "March 1999" or "1999-03-01".
int? parseYear(Object? value) {
  if (value is int) return value;
  if (value is! String) return null;
  final match = RegExp(r'\b(1[5-9]\d\d|20\d\d)\b').firstMatch(value);
  return match == null ? null : int.parse(match.group(1)!);
}
