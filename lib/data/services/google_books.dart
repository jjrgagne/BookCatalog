import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/isbn.dart';
import '../models/book.dart';
import '../models/book_metadata.dart';

/// Optional Google Books API key, passed with
/// `--dart-define=GOOGLE_BOOKS_API_KEY=...`. Works without one at low volume.
const _apiKey = String.fromEnvironment('GOOGLE_BOOKS_API_KEY');

/// Looks up books on the Google Books API.
class GoogleBooksClient {
  GoogleBooksClient(this._http);

  final http.Client _http;

  Future<BookMetadata?> lookup(String isbn13) async {
    final uri = Uri.https('www.googleapis.com', '/books/v1/volumes', {
      'q': 'isbn:$isbn13',
      if (_apiKey.isNotEmpty) 'key': _apiKey,
    });
    final response = await _http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException('Google Books: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['items'] is! List) return null;
    final items = (body['items'] as List).whereType<Map>();
    if (items.isEmpty) return null;
    final info = items.first['volumeInfo'];
    if (info is! Map) return null;
    return parse(isbn13, info.cast<String, Object?>());
  }

  static BookMetadata? parse(String isbn13, Map<String, Object?> info) {
    final title = (info['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;

    String? isbn10;
    final ids = info['industryIdentifiers'];
    if (ids is List) {
      for (final id in ids.whereType<Map>()) {
        if (id['type'] == 'ISBN_10') isbn10 = id['identifier'] as String?;
      }
    }

    final images = info['imageLinks'];
    String? coverUrl;
    if (images is Map) {
      coverUrl = (images['thumbnail'] ?? images['smallThumbnail']) as String?;
    }

    final authors = info['authors'];
    return BookMetadata(
      isbn13: isbn13,
      isbn10: isbn10 ?? toIsbn10(isbn13),
      title: title,
      subtitle: (info['subtitle'] as String?)?.trim(),
      authors: authors is List ? authors.whereType<String>().toList() : [],
      publisher: info['publisher'] as String?,
      publishedYear: parseYear(info['publishedDate']),
      coverUrl: coverUrl?.replaceFirst('http://', 'https://'),
      source: MetadataSource.google,
    );
  }
}
