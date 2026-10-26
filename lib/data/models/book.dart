import 'ids.dart';

/// Where a book's details came from.
enum MetadataSource {
  openlibrary,
  google,
  manual,

  /// Saved from a scan whose lookup hasn't completed yet (e.g. offline).
  pending;

  static MetadataSource parse(Object? value) => MetadataSource.values
      .firstWhere((e) => e.name == value, orElse: () => MetadataSource.manual);
}

class Book {
  const Book({
    required this.id,
    required this.title,
    this.isbn13,
    this.isbn10,
    this.subtitle,
    this.authors = const [],
    this.publisher,
    this.publishedYear,
    this.coverUrl,
    this.locationId,
    this.previousLocationId,
    this.tagIds = const [],
    this.copies = 1,
    this.notes = '',
    this.metadataSource = MetadataSource.manual,
    this.addedBy,
    required this.addedAt,
    required this.updatedAt,
  });

  final String id;
  final String? isbn13;
  final String? isbn10;
  final String title;
  final String? subtitle;
  final List<String> authors;
  final String? publisher;
  final int? publishedYear;
  final String? coverUrl;
  final String? locationId;

  /// The room a book was in before it was lent to a person; used by Return.
  final String? previousLocationId;
  final List<String> tagIds;
  final int copies;
  final String notes;
  final MetadataSource metadataSource;
  final String? addedBy;
  final DateTime addedAt;
  final DateTime updatedAt;

  String get authorsText => authors.join(', ');

  Book copyWith({
    Object? isbn13 = unset,
    Object? isbn10 = unset,
    String? title,
    Object? subtitle = unset,
    List<String>? authors,
    Object? publisher = unset,
    Object? publishedYear = unset,
    Object? coverUrl = unset,
    Object? locationId = unset,
    Object? previousLocationId = unset,
    List<String>? tagIds,
    int? copies,
    String? notes,
    MetadataSource? metadataSource,
    DateTime? updatedAt,
  }) {
    return Book(
      id: id,
      isbn13: isbn13 == unset ? this.isbn13 : isbn13 as String?,
      isbn10: isbn10 == unset ? this.isbn10 : isbn10 as String?,
      title: title ?? this.title,
      subtitle: subtitle == unset ? this.subtitle : subtitle as String?,
      authors: authors ?? this.authors,
      publisher: publisher == unset ? this.publisher : publisher as String?,
      publishedYear: publishedYear == unset
          ? this.publishedYear
          : publishedYear as int?,
      coverUrl: coverUrl == unset ? this.coverUrl : coverUrl as String?,
      locationId: locationId == unset ? this.locationId : locationId as String?,
      previousLocationId: previousLocationId == unset
          ? this.previousLocationId
          : previousLocationId as String?,
      tagIds: tagIds ?? this.tagIds,
      copies: copies ?? this.copies,
      notes: notes ?? this.notes,
      metadataSource: metadataSource ?? this.metadataSource,
      addedBy: addedBy,
      addedAt: addedAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, Object?> toMap() => {
    'isbn13': isbn13,
    'isbn10': isbn10,
    'title': title,
    'subtitle': subtitle,
    'authors': authors,
    'publisher': publisher,
    'publishedYear': publishedYear,
    'coverUrl': coverUrl,
    'locationId': locationId,
    'previousLocationId': previousLocationId,
    'tagIds': tagIds,
    'copies': copies,
    'notes': notes,
    'metadataSource': metadataSource.name,
    'addedBy': addedBy,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory Book.fromMap(String id, Map<String, Object?> map) {
    DateTime time(Object? v) => v is int
        ? DateTime.fromMillisecondsSinceEpoch(v)
        : DateTime.fromMillisecondsSinceEpoch(0);
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : const [];
    return Book(
      id: id,
      isbn13: map['isbn13'] as String?,
      isbn10: map['isbn10'] as String?,
      title: (map['title'] as String?) ?? '',
      subtitle: map['subtitle'] as String?,
      authors: strings(map['authors']),
      publisher: map['publisher'] as String?,
      publishedYear: (map['publishedYear'] as num?)?.toInt(),
      coverUrl: map['coverUrl'] as String?,
      locationId: map['locationId'] as String?,
      previousLocationId: map['previousLocationId'] as String?,
      tagIds: strings(map['tagIds']),
      copies: (map['copies'] as num?)?.toInt() ?? 1,
      notes: (map['notes'] as String?) ?? '',
      metadataSource: MetadataSource.parse(map['metadataSource']),
      addedBy: map['addedBy'] as String?,
      addedAt: time(map['addedAt']),
      updatedAt: time(map['updatedAt']),
    );
  }
}
