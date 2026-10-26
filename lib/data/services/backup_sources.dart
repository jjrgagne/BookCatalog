import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/isbn.dart';
import '../models/book.dart';
import '../models/book_metadata.dart';
import 'open_library.dart' show userAgent;

/// Open Library's search index, which sometimes knows editions that the
/// books API (used first) does not.
class OpenLibrarySearchClient {
  OpenLibrarySearchClient(this._http);

  final http.Client _http;

  Future<BookMetadata?> lookup(String isbn13) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {
      'isbn': isbn13,
      'fields':
          'title,subtitle,author_name,publisher,first_publish_year,cover_i',
      'limit': '1',
    });
    final response = await _http
        .get(uri, headers: {'User-Agent': userAgent})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException('Open Library search: ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['docs'] is! List) return null;
    final docs = (body['docs'] as List).whereType<Map>();
    if (docs.isEmpty) return null;
    return parse(isbn13, docs.first.cast<String, Object?>());
  }

  static BookMetadata? parse(String isbn13, Map<String, Object?> doc) {
    final title = (doc['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : const [];
    final publishers = strings(doc['publisher']);
    final cover = doc['cover_i'];
    return BookMetadata(
      isbn13: isbn13,
      isbn10: toIsbn10(isbn13),
      title: title,
      subtitle: (doc['subtitle'] as String?)?.trim(),
      authors: strings(doc['author_name']),
      publisher: publishers.isEmpty ? null : publishers.first,
      publishedYear: parseYear(doc['first_publish_year']),
      coverUrl: cover is int
          ? 'https://covers.openlibrary.org/b/id/$cover-M.jpg'
          : null,
      source: MetadataSource.openlibrary,
    );
  }
}

/// Crossref, which covers many academic and professional books.
class CrossrefClient {
  CrossrefClient(this._http);

  final http.Client _http;

  Future<BookMetadata?> lookup(String isbn13) async {
    final uri = Uri.https('api.crossref.org', '/works', {
      'filter': 'isbn:$isbn13',
      'rows': '1',
    });
    final response = await _http
        .get(uri, headers: {'User-Agent': userAgent})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException('Crossref: ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    final items = body is Map && body['message'] is Map
        ? (body['message'] as Map)['items']
        : null;
    if (items is! List || items.isEmpty || items.first is! Map) return null;
    return parse(isbn13, (items.first as Map).cast<String, Object?>());
  }

  static BookMetadata? parse(String isbn13, Map<String, Object?> item) {
    String? first(Object? v) => v is List && v.isNotEmpty && v.first is String
        ? v.first as String
        : null;
    final title = first(item['title'])?.trim() ?? '';
    if (title.isEmpty) return null;

    final authors = <String>[];
    final people = item['author'] ?? item['editor'];
    if (people is List) {
      for (final p in people.whereType<Map>()) {
        final name = [p['given'], p['family']].whereType<String>().join(' ');
        if (name.isNotEmpty) authors.add(name);
      }
    }

    int? year;
    for (final key in ['published-print', 'published', 'issued']) {
      final parts = item[key];
      if (parts is Map && parts['date-parts'] is List) {
        final dp = parts['date-parts'] as List;
        if (dp.isNotEmpty &&
            dp.first is List &&
            (dp.first as List).isNotEmpty) {
          year = parseYear((dp.first as List).first);
          if (year != null) break;
        }
      }
    }

    return BookMetadata(
      isbn13: isbn13,
      isbn10: toIsbn10(isbn13),
      title: title,
      subtitle: first(item['subtitle'])?.trim(),
      authors: authors,
      publisher: item['publisher'] as String?,
      publishedYear: year,
      source: MetadataSource.crossref,
    );
  }
}

/// Cover image by ISBN from Open Library; returns 404 (shown as the
/// placeholder) when there is none.
String openLibraryCoverByIsbn(String isbn13) =>
    'https://covers.openlibrary.org/b/isbn/$isbn13-M.jpg?default=false';

/// Web searches the user can open when no source knows a book. Amazon has no
/// free lookup API, so it is offered as a link rather than queried directly.
class WebSearch {
  const WebSearch(this.label, this.url);
  final String label;
  final Uri url;
}

List<WebSearch> webSearchesFor(String isbn13) => [
  WebSearch(
    'Amazon',
    Uri.https('www.amazon.com', '/s', {'k': isbn13, 'i': 'stripbooks'}),
  ),
  WebSearch(
    'AbeBooks',
    Uri.https('www.abebooks.com', '/servlet/SearchResults', {'isbn': isbn13}),
  ),
  WebSearch(
    'Google',
    Uri.https('www.google.com', '/search', {'q': 'ISBN $isbn13'}),
  ),
];
