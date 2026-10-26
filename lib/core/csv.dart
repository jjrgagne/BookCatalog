import '../data/models/book.dart';
import '../data/models/location.dart';
import '../data/models/tag.dart';

String _cell(Object? value) {
  final s = value?.toString() ?? '';
  if (s.contains(RegExp(r'[",\r\n]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

/// Exports the catalog as CSV (RFC 4180, CRLF line endings) with location
/// and tag names resolved, sorted by title.
String booksToCsv(
  List<Book> books,
  Map<String, Location> locations,
  Map<String, Tag> tags,
) {
  const header = [
    'ISBN-13',
    'ISBN-10',
    'Title',
    'Subtitle',
    'Authors',
    'Publisher',
    'Year',
    'Location',
    'Location type',
    'On loan from',
    'Tags',
    'Copies',
    'Notes',
    'Added',
  ];
  final sorted = [...books]
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  final rows = <List<Object?>>[
    header,
    for (final b in sorted)
      [
        b.isbn13,
        b.isbn10,
        b.title,
        b.subtitle,
        b.authors.join('; '),
        b.publisher,
        b.publishedYear,
        locations[b.locationId]?.name,
        locations[b.locationId]?.kind.name,
        locations[b.previousLocationId]?.name,
        b.tagIds.map((t) => tags[t]?.name).whereType<String>().join('; '),
        b.copies,
        b.notes,
        b.addedAt.toIso8601String().substring(0, 10),
      ],
  ];
  return '${rows.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';
}
