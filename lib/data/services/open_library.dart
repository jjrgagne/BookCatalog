import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/isbn.dart';
import '../models/book.dart';
import '../models/book_metadata.dart';

const userAgent = 'BookCatalog/1.0 (+https://github.com/jjrgagne/BookCatalog)';

/// Looks up books on Open Library (no API key needed).
class OpenLibraryClient {
  OpenLibraryClient(this._http);

  final http.Client _http;

  Future<BookMetadata?> lookup(String isbn13) async {
    final uri = Uri.https('openlibrary.org', '/api/books', {
      'bibkeys': 'ISBN:$isbn13',
      'format': 'json',
      'jscmd': 'data',
    });
    final response = await _http
        .get(uri, headers: {'User-Agent': userAgent})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException('Open Library: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body.isEmpty) return null;
    final data = body['ISBN:$isbn13'];
    if (data is! Map) return null;
    return parse(isbn13, data.cast<String, Object?>());
  }

  static BookMetadata? parse(String isbn13, Map<String, Object?> data) {
    final title = (data['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;

    List<String> names(Object? list) => list is List
        ? list
              .whereType<Map>()
              .map((e) => (e['name'] as String?)?.trim())
              .whereType<String>()
              .where((e) => e.isNotEmpty)
              .toList()
        : const [];

    final identifiers = data['identifiers'];
    String? isbn10;
    if (identifiers is Map && identifiers['isbn_10'] is List) {
      final list = (identifiers['isbn_10'] as List).whereType<String>();
      isbn10 = list.isEmpty ? null : normalizeIsbn(list.first);
    }

    final cover = data['cover'];
    String? coverUrl;
    if (cover is Map) {
      coverUrl =
          (cover['medium'] ?? cover['large'] ?? cover['small']) as String?;
    }

    final publishers = names(data['publishers']);
    return BookMetadata(
      isbn13: isbn13,
      isbn10: isbn10 ?? toIsbn10(isbn13),
      title: title,
      subtitle: (data['subtitle'] as String?)?.trim(),
      authors: names(data['authors']),
      publisher: publishers.isEmpty ? null : publishers.first,
      publishedYear: parseYear(data['publish_date']),
      coverUrl: coverUrl?.replaceFirst('http://', 'https://'),
      source: MetadataSource.openlibrary,
    );
  }
}
